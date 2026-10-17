#!/usr/bin/env python3
"""Real Sirb/CEF fixture: manual media start, frame sandbox and diagnostics.
Launch an isolated Sirb with opt-in loopback CDP and a web tab first.
Requires websocket-client and ffmpeg; no remote media or sandbox overrides.
"""
import argparse
import http.server
import json
import pathlib
import sqlite3
import subprocess
import tempfile
import threading
import time
import urllib.request

from verify_game import CDP

MEDIA = '''<video id="media" src="/clip.webm" width="320" height="180"
 controls muted autoplay loop></video>
<div class="bottom"><div class="bar"><div class="left"><div class="inner">
<button id="start" onclick="media.play()"><svg id="starticon" width="24" height="24"><path d="M 2,2 L 22,12 L 2,22 Z"/></svg>Play</button>
</div></div></div></div>
<script>
window.attempt='pending';
media.play().then(()=>attempt='played',e=>attempt=e.name);
</script>'''
HTML = ('''<!doctype html><title>Sirb manual playback fixture</title><div id="player">''' + MEDIA + '''</div>
<button id="unrelated">Unrelated page action</button>
<a id="open" href="/child.html" target="_blank">New tab</a>
<iframe id="utility" sandbox src="about:blank"></iframe>
<iframe id="child" src="/child.html"></iframe>''').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=9243)
    parser.add_argument('--database', required=True)
    parser.add_argument('--output', default='build/manual-playback-evidence')
    args = parser.parse_args()
    db = sqlite3.connect(args.database)
    start = db.execute('SELECT COALESCE(MAX(id),0) FROM error_logs').fetchone()[0]
    with tempfile.TemporaryDirectory(prefix='sirb-manual-media-') as directory:
        clip_path = pathlib.Path(directory)/'clip.webm'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i',
                        'testsrc2=size=320x180:rate=15', '-t', '6', '-c:v', 'libvpx-vp9',
                        '-threads', '2', str(clip_path)], check=True)
        clip = clip_path.read_bytes()

        class Fixture(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                if self.path == '/clip.webm':
                    body, mime = clip, 'video/webm'
                elif self.path == '/child.html':
                    body, mime = ('<!doctype html><div>'+MEDIA+'</div>').encode(), 'text/html'
                else:
                    body, mime = HTML, 'text/html'
                self.send_response(200)
                self.send_header('Content-Type', mime)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}/fixture.html'
        with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list') as response:
            pages = [t for t in json.load(response) if t['type'] == 'page']
        if not pages:
            raise RuntimeError('Open a web tab in the isolated Sirb profile first')
        page = CDP(pages[0]['webSocketDebuggerUrl'])
        try:
            page.call('Page.enable')
            page.call('Page.navigate', url=url)
            time.sleep(3)
            state = page.evaluate('''({telemetry:!!window.__sirbTelemetry,
              active:navigator.userActivation.hasBeenActive,attempt,paused:media.paused,time:media.currentTime,
              childPaused:child.contentDocument.querySelector('video').paused,
              childAttempt:child.contentWindow.attempt,
              sandbox:utility.getAttribute('sandbox')})''')
            assert state['telemetry'] and not state['active'], state
            assert state['paused'] and state['time'] < .05 and state['attempt'] == 'NotAllowedError', state
            assert state['childPaused'] and state['childAttempt'] == 'NotAllowedError', state
            assert state['sandbox'] == '', 'Sandbox permissions were modified'
            # Synthetic events do not count as user activation.
            page.evaluate('start.click()')
            time.sleep(.3)
            assert page.evaluate('media.paused'), 'Synthetic click unlocked autoplay'
            def click(element_id):
                rect = page.evaluate('(()=>{const r=document.getElementById('+json.dumps(element_id)+').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};})()')
                for kind in ['mousePressed', 'mouseReleased']:
                    page.call('Input.dispatchMouseEvent', type=kind, button='left', clickCount=1, **rect)

            click('unrelated')
            assert page.evaluate('navigator.userActivation.hasBeenActive'), 'Fixture click was not trusted'
            unrelated = page.evaluate("media.play().then(()=>'played',e=>e.name)")
            assert unrelated == 'NotAllowedError', 'Unrelated page click unlocked autoplay'
            click('start')
            time.sleep(1)
            playing = page.evaluate('({paused:media.paused,time:media.currentTime,active:navigator.userActivation.hasBeenActive})')
            assert playing['active'] and not playing['paused'] and playing['time'] > .2, playing
            page.evaluate('media.pause()')
            time.sleep(.5)
            assert page.evaluate('media.paused'), 'Manual pause was overridden'
            race = page.evaluate('''(async()=>{const p=media.play();media.pause();
              try{await p;return 'resolved';}catch(e){return e.name;}})()''')
            page.call('Page.reload')
            time.sleep(2)
            assert page.evaluate('media.paused && !navigator.userActivation.hasBeenActive'), 'Reload leaked activation'
            click('open')
            time.sleep(2)
            with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list') as response:
                after = [t for t in json.load(response) if t['type'] == 'page']
            opened = [t for t in after if t['id'] not in {p['id'] for p in pages}]
            assert len(opened) == 1, 'Trusted target=_blank did not open exactly one Sirb tab'
            popup = CDP(opened[0]['webSocketDebuggerUrl'])
            try:
                new_tab = popup.evaluate('({paused:media.paused,attempt,active:navigator.userActivation.hasBeenActive})')
                assert new_tab['paused'] and not new_tab['active'] and new_tab['attempt'] == 'NotAllowedError', new_tab
            finally:
                popup.close()
            time.sleep(1)
            rows = db.execute('SELECT type,message,url,details FROM error_logs WHERE id>? ORDER BY id', (start,)).fetchall()
            records = [dict(zip(['type', 'message', 'url', 'details'], row)) for row in rows]
            failures = [r for r in records if r['type'] != 'ad']
            assert not failures, failures
            result = {'result': 'PASS', 'initial': state, 'manualPlayback': playing,
                      'playPauseRace': race, 'unrelatedClickAttempt': unrelated,
                      'newTab': new_tab, 'records': records,
                      'limits': 'Local VP9 CEF fixture; not proof of live YouTube/CDN availability.'}
            out = pathlib.Path(args.output)
            out.mkdir(parents=True, exist_ok=True)
            (out/'manual-playback.json').write_text(json.dumps(result, indent=2))
            print(json.dumps(result, indent=2))
        finally:
            page.close()
            server.shutdown()
            db.close()


if __name__ == '__main__':
    main()
