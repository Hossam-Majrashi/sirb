#!/usr/bin/env python3
"""Hermetic Chromium smoke tests; no YouTube credentials or external requests.

  dart run tool/export_page_features.dart > /tmp/sirb-page-features.js
  python3 tool/verify_page_features.py /tmp/sirb-page-features.js

Requires chromium, chromedriver, openssl and Python requests. Uses a local HTTPS
fixture with a YouTube hostname to exercise the exact production host guards.
This verifies browser behavior, not YouTube's current server-side schemas.
"""
import collections
import http.server
import json
import pathlib
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

import requests


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


COUNTS = collections.Counter()
METADATA_COOKIES = []
LOCK = threading.Lock()
FIXTURE = '''<!doctype html><html><head><style>
body{margin:0;min-height:10000px}a{display:block;width:300px;height:35px}
#comments,#secondary{position:absolute;top:6000px;width:400px;height:200px}
#secondary{left:500px}#hidden-card{position:absolute;top:9000px}
#image-container{position:absolute;top:8000px;width:300px;height:200px}
</style></head><body>
<a id="video-title" href="/watch?v=aaaaaaaaaaa">عنوان مترجم أ</a>
<a id="video-title-link" href="/watch?v=aaaaaaaaaaa"><yt-formatted-string id="video-title">عنوان مكرر</yt-formatted-string></a>
<a class="yt-lockup-metadata-view-model__title" href="/watch?v=bbbbbbbbbbb">عنوان مترجم ب</a>
<a id="hidden-card" class="yt-lockup-metadata-view-model__title" href="/watch?v=ddddddddddd">عنوان مخفي</a>
<div style="overflow:hidden;height:0"><a id="video-title" href="/watch?v=ggggggggggg">Clipped title</a></div>
<ytd-comments id="comments"></ytd-comments>
<ytd-watch-flexy><div id="secondary"><ytd-watch-next-secondary-results-renderer></ytd-watch-next-secondary-results-renderer></div></ytd-watch-flexy>
<div id="image-container"></div>
<script>
document.cookie='private_probe=do-not-send';
document.querySelector('#comments').data={continuationEndpoint:{continuationCommand:{token:'comments-token'}}};
document.querySelector('ytd-watch-next-secondary-results-renderer').data={continuationEndpoint:{continuationCommand:{token:'sidebar-token'}}};
window.sendNext=(token,signal)=>fetch('/youtubei/v1/next',{method:'POST',body:JSON.stringify({continuation:token}),signal});
</script></body></html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        key = url.path
        if key == '/oembed':
            video = urllib.parse.parse_qs(url.query)['url'][0]
            video_id = urllib.parse.parse_qs(urllib.parse.urlsplit(video).query)['v'][0]
            key += ':' + video_id
            with LOCK:
                METADATA_COOKIES.append(self.headers.get('Cookie'))
        with LOCK:
            COUNTS[key] += 1
        status, mime, body = 200, 'text/html; charset=utf-8', FIXTURE.encode()
        if url.path == '/oembed':
            time.sleep(0.25 if video_id != 'fffffffffff' else 1)
            status = 404 if video_id == 'eeeeeeeeeee' else 200
            mime, body = 'application/json', json.dumps({'title': 'Original ' + video_id}).encode()
        elif url.path.endswith('.svg'):
            mime, body = 'image/svg+xml', b'<svg xmlns="http://www.w3.org/2000/svg" width="300" height="200"/>'
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ssl.SSLError):
            pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        token = json.loads(body or '{}').get('continuation', 'initial')
        with LOCK:
            COUNTS[self.path + ':' + token] += 1
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{}')


def main():
    script = pathlib.Path(sys.argv[1]).read_text()
    client = requests.Session()
    client.trust_env = False
    driver = None
    session = None
    server = None
    with tempfile.TemporaryDirectory(prefix='sirb-page-features-') as tmp:
        tmp = pathlib.Path(tmp)
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(tmp / 'key.pem'), '-out', str(tmp / 'cert.pem'),
                        '-days', '1', '-subj', '/CN=www.youtube.com'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(tmp / 'cert.pem', tmp / 'key.pem')
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = free_port()
        log = open(tmp / 'driver.log', 'w')
        driver = subprocess.Popen(['chromedriver', f'--port={port}'], stdout=log, stderr=log)
        endpoint = f'http://127.0.0.1:{port}'

        def command(path, payload=None):
            response = client.post(endpoint + path, json=payload or {}, timeout=25)
            response.raise_for_status()
            value = response.json()['value']
            if isinstance(value, dict) and 'error' in value:
                raise RuntimeError(value)
            return value

        def wait_for(predicate, label, timeout=8):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    if predicate():
                        return
                except requests.ConnectionError:
                    pass
                time.sleep(0.05)
            raise AssertionError(label)

        try:
            wait_for(lambda: client.get(endpoint + '/status').ok, 'chromedriver starts')
            result = command('/session', {'capabilities': {'alwaysMatch': {
                'browserName': 'chrome', 'goog:chromeOptions': {'args': [
                    '--headless=new', '--no-sandbox', '--disable-dev-shm-usage',
                    '--no-proxy-server', '--ignore-certificate-errors',
                    '--disable-background-networking', '--disable-component-update',
                    '--disable-sync', '--window-size=1280,800',
                    '--host-resolver-rules=MAP www.youtube.com 127.0.0.1',
                ]}}}})
            session = result['sessionId']
            prefix = '/session/' + session

            def js(source):
                return command(prefix + '/execute/sync', {'script': source, 'args': []})

            command(prefix + '/goog/cdp/execute', {
                'cmd': 'Page.addScriptToEvaluateOnNewDocument', 'params': {'source': script}})
            origin = f'https://www.youtube.com:{server.server_port}'
            command(prefix + '/url', {'url': origin + '/watch?v=aaaaaaaaaaa'})
            wait_for(lambda: js("return document.querySelector('#video-title').textContent") == 'Original aaaaaaaaaaa', 'visible original title')
            wait_for(lambda: js("return document.querySelector('#video-title-link').textContent") == 'Original aaaaaaaaaaa', 'duplicate shares metadata')
            assert COUNTS['/oembed:aaaaaaaaaaa'] == 1, COUNTS
            assert COUNTS['/oembed:ddddddddddd'] == 0, 'hidden cards must not fetch metadata'
            assert COUNTS['/oembed:ggggggggggg'] == 0, 'clipped cards must not fetch metadata'
            assert js("return !!document.querySelector('#video-title-link yt-formatted-string')"), 'preserve component structure'
            assert not any(METADATA_COOKIES), METADATA_COOKIES
            js('window.savedFetch=window.fetch')
            js(script)
            assert js('return window.savedFetch===window.fetch'), 'live injection must be idempotent'
            assert COUNTS['/oembed:aaaaaaaaaaa'] == 1

            # Actual image data is withheld for dynamic off-screen src writes.
            js("""const box=document.querySelector('#image-container');
              const image=new Image(300,200);image.id='lazy-probe';image.src='/lazy.svg';box.append(image);
              const eager=new Image(300,200);eager.loading='eager';eager.src='/eager.svg';box.append(eager);
              const attributes=new Image(300,200);attributes.setAttribute('srcset','/srcset.svg 1x');box.append(attributes);
              const frame=document.createElement('iframe');frame.width=0;frame.height=0;frame.src='about:blank';box.append(frame);
              window.utilityFrameIsEager=!frame.hasAttribute('loading');""")
            wait_for(lambda: COUNTS['/eager.svg'] == 1, 'site eager priority honoured')
            time.sleep(0.4)
            assert COUNTS['/lazy.svg'] == 0 and COUNTS['/srcset.svg'] == 0, COUNTS
            assert js('return window.utilityFrameIsEager')

            # Initial/unknown/player requests cannot be starved.
            js("""window.sendNext('unknown');window.sendNext(undefined);
              fetch('/youtubei/v1/player',{method:'POST',body:'{}'});
              window.commentDone=false;window.sendNext('comments-token').then(()=>window.commentDone=true);
              window.sidebarDone=false;window.sendNext('sidebar-token').then(()=>window.sidebarDone=true);""")
            wait_for(lambda: COUNTS['/youtubei/v1/player:initial'] == 1, 'player passes through')
            assert COUNTS['/youtubei/v1/next:unknown'] == 1
            assert COUNTS['/youtubei/v1/next:initial'] == 1
            time.sleep(0.3)
            assert COUNTS['/youtubei/v1/next:comments-token'] == 0
            assert COUNTS['/youtubei/v1/next:sidebar-token'] == 0
            js('scrollTo(0,5800)')
            wait_for(lambda: js('return window.commentDone && window.sidebarDone'), 'visible sections resume')
            assert COUNTS['/youtubei/v1/next:comments-token'] == 1
            js('scrollTo(0,7800)')
            wait_for(lambda: COUNTS['/lazy.svg'] == 1 and COUNTS['/srcset.svg'] == 1, 'lazy images resume on scroll')
            js('scrollTo(0,0)')

            # Abort and SPA navigation must not transmit stale continuations.
            js("""window.abortResult=null;const controller=new AbortController();
              window.sendNext('comments-token',controller.signal).catch(e=>window.abortResult=e.name);controller.abort();""")
            wait_for(lambda: js('return window.abortResult') == 'AbortError', 'abort semantics')
            assert COUNTS['/youtubei/v1/next:comments-token'] == 1
            js("""window.navResult=null;window.sendNext('comments-token').catch(e=>window.navResult=e.name);
              history.pushState({},'', '/watch?v=bbbbbbbbbbb');dispatchEvent(new Event('yt-navigate-finish'));""")
            wait_for(lambda: js('return window.navResult') == 'AbortError', 'SPA cancels stale continuations')
            assert COUNTS['/youtubei/v1/next:comments-token'] == 1

            # Turning focus loading off releases both queued fetches and images.
            js("""window.releaseDone=false;window.sendNext('sidebar-token').then(()=>window.releaseDone=true);
              window.__sirbFocusLoading=false;window.__sirbFlushYoutubeRequests();window.__sirbUpdateFocusLoading();""")
            wait_for(lambda: js('return window.releaseDone'), 'live toggle flush')
            assert js("return !document.querySelector('#lazy-probe').hasAttribute('loading')")

            # Bound the delay even if YouTube changes layout and no event fires.
            js("""window.__sirbFocusLoading=true;window.timeoutDone=false;
              window.sendNext('comments-token').then(()=>window.timeoutDone=true);""")
            wait_for(lambda: js('return window.timeoutDone'), '15 second fail-open', timeout=17)

            # Metadata failures preserve site titles; reused SPA cards reject old responses.
            js("""const link=document.querySelector('#video-title');link.href='/watch?v=eeeeeeeeeee';link.textContent='Keep this title';""")
            wait_for(lambda: COUNTS['/oembed:eeeeeeeeeee'] == 1, 'failed metadata attempted once')
            time.sleep(0.6)
            assert js("return document.querySelector('#video-title').textContent") == 'Keep this title'
            js("""const link=document.querySelector('#video-title');link.href='/watch?v=fffffffffff';link.textContent='Old card';""")
            wait_for(lambda: COUNTS['/oembed:fffffffffff'] == 1, 'slow old lookup starts')
            js("""const link=document.querySelector('#video-title');link.href='/watch?v=ccccccccccc';link.textContent='New card';""")
            wait_for(lambda: js("return document.querySelector('#video-title').textContent") == 'Original ccccccccccc', 'new card title')
            time.sleep(1)
            assert js("return document.querySelector('#video-title').textContent") == 'Original ccccccccccc'
            js('window.__sirbOriginalTitles=false;window.__sirbUpdateOriginalTitles()')
            assert js("return document.querySelector('#video-title').textContent") == 'New card'
            count_before = COUNTS['/youtubei/v1/next:comments-token']
            js("""window.pagehideResult=null;window.sendNext('comments-token').catch(e=>window.pagehideResult=e.name);
              dispatchEvent(new PageTransitionEvent('pagehide'));""")
            wait_for(lambda: js('return window.pagehideResult') == 'AbortError', 'pagehide cancels queued requests')
            assert COUNTS['/youtubei/v1/next:comments-token'] == count_before
            print(json.dumps({'result': 'PASS', 'requests': dict(COUNTS),
                              'metadata_cookies_sent': any(METADATA_COOKIES)}, indent=2))
        finally:
            if session:
                client.delete(endpoint + '/session/' + session, timeout=10)
            if driver:
                driver.terminate()
                driver.wait(timeout=10)
            log.close()
            server.shutdown()


if __name__ == '__main__':
    main()
