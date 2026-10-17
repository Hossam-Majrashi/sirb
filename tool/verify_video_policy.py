#!/usr/bin/env python3
"""Hermetic Chromium fixtures, not a claim about live platform ad delivery.

dart run tool/export_video_policy.dart > /tmp/sirb-video-policy.json
python3 tool/verify_video_policy.py /tmp/sirb-video-policy.json
Requires chromium/chromedriver, ffmpeg, openssl and Python requests.
"""
import http.server
import json
import pathlib
import ssl
import subprocess
import sys
import tempfile
import threading
import time

from verify_page_features import free_port
import requests


FIXTURE = b'''<!doctype html><html><body>
<div id="banner" class="advertisement" data-testid="ad-banner">Ad banner</div>
<div id="movie_player" aria-label="Advertisement" style="width:640px;height:360px">
<video id="media" width="640" height="360" muted loop controls preload="metadata" src="/clip.webm"></video>
<button id="control">Play</button></div>
<div data-a-target="video-ad-label" id="countdown">Ad countdown</div>
<div class="stream-display-ad" id="twitch-banner">Twitch ad banner</div>
</body></html>'''


def main():
    policy = json.loads(pathlib.Path(sys.argv[1]).read_text())
    client = requests.Session()
    client.trust_env = False
    with tempfile.TemporaryDirectory(prefix='sirb-video-policy-') as directory:
        tmp = pathlib.Path(directory)
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(tmp/'key'), '-out', str(tmp/'cert'), '-days', '1',
                        '-subj', '/CN=fixture'], check=True, capture_output=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i',
                        'testsrc2=size=320x180:rate=15', '-t', '6', '-c:v', 'libvpx-vp9',
                        '-threads', '2', str(tmp/'clip.webm')], check=True)
        clip = (tmp/'clip.webm').read_bytes()

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                media = self.path.startswith('/clip.webm')
                body = clip if media else FIXTURE
                self.send_response(200)
                self.send_header('Content-Type', 'video/webm' if media else 'text/html')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(tmp/'cert', tmp/'key')
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = free_port()
        log = open(tmp/'driver.log', 'w')
        driver = subprocess.Popen(['chromedriver', f'--port={port}'], stdout=log, stderr=log)
        endpoint = f'http://127.0.0.1:{port}'
        prefix = None

        def command(path, payload=None):
            response = client.post(endpoint+path, json=payload or {}, timeout=25)
            response.raise_for_status()
            result = response.json()['value']
            if isinstance(result, dict) and isinstance(result.get('error'), str):
                raise RuntimeError(result)
            return result

        def wait(predicate, message, timeout=8):
            deadline = time.monotonic()+timeout
            while time.monotonic() < deadline:
                try:
                    if predicate():
                        return
                except requests.ConnectionError:
                    pass
                time.sleep(.05)
            raise AssertionError(message)

        def js(source):
            return command(prefix+'/execute/sync', {'script': source, 'args': []})

        def navigate(host):
            command(prefix+'/url', {'url': f'https://{host}:{server.server_port}/fixture'})
            wait(lambda: js('return document.readyState') == 'complete', 'document ready')

        def fake_ad(source='ad-one', duration=30):
            js('''const player=document.querySelector('#movie_player');
                player.innerHTML='<video id="fake"></video><button class="ytp-ad-skip-button">Skip</button>';
                window.probe={seeks:0,clicks:0,time:0,source:arguments[0]};'''.replace('arguments[0]', json.dumps(source)))
            js(f'''const video=document.querySelector('#fake');
                Object.defineProperties(video,{{
                  duration:{{configurable:true,get:()=>{duration}}},currentSrc:{{get:()=>probe.source}},
                  currentTime:{{get:()=>probe.time,set:value=>{{probe.seeks++;probe.time=value;}}}}
                }});
                document.querySelector('.ytp-ad-skip-button').onclick=()=>probe.clicks++;
                document.querySelector('#movie_player').className='ad-showing';''')

        try:
            wait(lambda: client.get(endpoint+'/status').ok, 'driver starts')
            session = command('/session', {'capabilities': {'alwaysMatch': {
                'browserName': 'chrome', 'goog:chromeOptions': {'args': [
                    '--headless=new', '--no-sandbox', '--disable-dev-shm-usage',
                    '--no-proxy-server', '--ignore-certificate-errors',
                    '--disable-background-networking', '--autoplay-policy=no-user-gesture-required',
                    '--host-resolver-rules=MAP *.youtube.com 127.0.0.1, MAP *.twitch.tv 127.0.0.1, MAP kick.com 127.0.0.1, MAP unrelated.test 127.0.0.1',
                ]}}}})['sessionId']
            prefix = '/session/'+session
            command(prefix+'/goog/cdp/execute', {'cmd': 'Page.addScriptToEvaluateOnNewDocument',
                'params': {'source': policy['ads']+'\n'+policy['priority']}})
            playback = {}
            for host in ['www.youtube.com', 'www.twitch.tv', 'kick.com', 'unrelated.test']:
                navigate(host)
                assert js("return getComputedStyle(document.querySelector('#banner')).display") == 'none'
                assert js("return getComputedStyle(document.querySelector('#movie_player')).display") != 'none'
                assert js("return getComputedStyle(document.querySelector('#media')).display") != 'none'
                assert js("return getComputedStyle(document.querySelector('#countdown')).display") != 'none'
                assert js('return !!window.__sirbYouTube') == ('youtube.com' in host)
                if 'twitch.tv' in host:
                    assert js("return getComputedStyle(document.querySelector('#twitch-banner')).display") == 'none'
                # Native and custom controls get a local buffering hint; no auto-play.
                js("document.querySelector('#control').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,button:0}))")
                assert js("return document.querySelector('#media').preload") == 'auto'
                assert js("return document.querySelector('#media').paused"), 'no forced playback'
                js("document.querySelector('#media').play()")
                wait(lambda: js("return document.querySelector('#media').currentTime>.3"), 'media progresses')
                js("document.querySelector('#media').pause();document.querySelector('#media').currentTime=2")
                wait(lambda: js("return !document.querySelector('#media').seeking"), 'seek settles')
                assert js("return document.querySelector('#media').paused"), 'seek keeps user pause'
                js("document.querySelector('#media').play()")
                wait(lambda: js("return document.querySelector('#media').currentTime>2.3"), 'resumes after seek')
                playback[host] = js("const v=document.querySelector('#media');return {position:v.currentTime,error:v.error,decoded:v.getVideoPlaybackQuality().totalVideoFrames}")
                js('''window.sheetProbe={sheet:document.querySelector('#sirb-cosmetic'),mutations:0};
                  window.sheetObserver=new MutationObserver(records=>{
                    for(const r of records)if(r.target===sheetProbe.sheet ||
                      [...r.addedNodes,...r.removedNodes].includes(sheetProbe.sheet))sheetProbe.mutations++;
                  });sheetObserver.observe(document,{childList:true,subtree:true,characterData:true});''')
                js(policy['ads'])
                assert js("return document.querySelectorAll('#sirb-cosmetic').length") == 1
                assert js("return document.querySelector('#sirb-cosmetic')===sheetProbe.sheet"), 'reuse the live cosmetic sheet'
                assert js('return sheetProbe.mutations') == 0, 'unchanged policy must not churn layout styles'
                js('sheetObserver.disconnect()')
                js(policy['excepted'])
                assert js('return window.__sirbBlocking') == (host == 'unrelated.test')
                if host != 'unrelated.test':
                    assert js("return !document.querySelector('#sirb-cosmetic')"), 'site exception removes the old sheet'

            navigate('www.youtube.com')
            assert js("return !('adPlacements' in JSON.parse('{\"adPlacements\":[],\"videoDetails\":{}}'))")
            js("window.__sirbBlocking=false")
            assert js("return 'adPlacements' in JSON.parse('{\"adPlacements\":[]}')")
            js(policy['ads'])
            fake_ad()
            wait(lambda: js('return probe.seeks') == 1, 'one ad seek')
            js("for(let i=0;i<500;i++)document.querySelector('.ytp-ad-skip-button').classList.toggle('probe')")
            time.sleep(1.3)
            assert js('return probe.seeks') == 1, 'no repeated seeks during ad-state delay'
            assert 1 <= js('return probe.clicks') <= 2, 'bounded skip clicks'
            js("Object.defineProperty(document.querySelector('#fake'),'duration',{get:()=>30.1});probe.time=1")
            time.sleep(.3)
            assert js('return probe.seeks') == 1, 'duration drift/user seek must not repeat ad seeking'
            js('probe.source="ad-two";probe.time=0')
            wait(lambda: js('return probe.seeks') == 2, 'next ad source handled')
            js('window.__sirbBlocking=false;probe.source="ad-three";probe.time=0')
            time.sleep(.4)
            assert js('return probe.seeks') == 2, 'shield off stops intervention'
            js(policy['ads'])
            wait(lambda: js('return probe.seeks') == 3, 'shield on resumes without reload')
            js("document.querySelector('#movie_player').className='';probe.time=0")
            time.sleep(.3)
            assert js('return probe.time') == 0, 'normal content untouched'
            fake_ad('live', 'Infinity')
            time.sleep(.4)
            assert js('return probe.seeks') == 0, 'live stream never sought'
            js("dispatchEvent(new PageTransitionEvent('pagehide',{persisted:true}))")
            fake_ad('restored', 30)
            time.sleep(.3)
            assert js('return probe.seeks') == 0, 'pagehide suspends work'
            js("dispatchEvent(new PageTransitionEvent('pageshow',{persisted:true}))")
            wait(lambda: js('return probe.seeks') == 1, 'bfcache lifecycle resumes')
            # Priority code must not touch speculative players.
            js("window.__sirbSpeculative=true;document.querySelector('#fake').preload='none';document.querySelector('#fake').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))")
            assert js("return document.querySelector('#fake').preload") == 'none'
            navigate('unrelated.test')
            js("""const hidden=document.createElement('video');hidden.id='offscreen';hidden.width=640;hidden.height=360;hidden.style.position='absolute';hidden.style.top='9000px';document.body.append(hidden);
              const visible=document.createElement('video');visible.id='visible';visible.width=640;visible.height=360;document.querySelector('#movie_player').replaceChildren(visible);""")
            wait(lambda: js("return document.querySelector('#visible').preload") == 'auto', 'large visible video automatically prioritised')
            assert js("return !document.querySelector('#offscreen').hasAttribute('preload')"), 'no offscreen buffering'
            assert js("return document.querySelector('#visible').paused"), 'automatic hint is not autoplay'
            js("const extra=document.createElement('video');extra.id='extra';extra.width=640;extra.height=360;document.querySelector('#movie_player').replaceChildren(extra)")
            time.sleep(.3)
            assert js("return !document.querySelector('#extra').hasAttribute('preload')"), 'only one automatic buffer hint per document'
            print(json.dumps({'result': 'PASS', 'playback': playback,
                              'ad_seeking': 'bounded; live/content untouched',
                              'limits': 'Local Chromium fixtures only; not live Twitch/Kick SSAI or native CEF stutter measurements.'}, indent=2))
        finally:
            if prefix:
                client.delete(endpoint+prefix, timeout=10)
            driver.terminate()
            driver.wait(timeout=10)
            server.shutdown()
            log.close()


if __name__ == '__main__':
    main()
