#!/usr/bin/env python3
"""Probe Sirb's actual embedded CEF over opt-in loopback CDP, not another browser.
Requires websocket-client, ffmpeg and a running Sirb started with
SIRB_CEF_SWITCHES=remote-debugging-port=9227. Writes measured evidence only.
"""
import argparse
import base64
import functools
import http.server
import json
import pathlib
import sqlite3
import subprocess
import threading
import time
import urllib.request
import websocket

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, default=9227)
parser.add_argument('--fixture-port',type=int,default=0)
parser.add_argument('--expect-persistence',action='store_true')
parser.add_argument('--profile-data', required=True)
parser.add_argument('--output', default='build/runtime-evidence')
args = parser.parse_args()
out = pathlib.Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
fixtures = out / 'fixtures'
fixtures.mkdir(exist_ok=True)

class CDP:
    def __init__(self, target):
        self.socket = websocket.create_connection(target['webSocketDebuggerUrl'], timeout=30, suppress_origin=True)
        self.sequence = 0
    def call(self, method, **params):
        self.sequence += 1
        self.socket.send(json.dumps({'id': self.sequence, 'method': method, 'params': params}))
        while True:
            message = json.loads(self.socket.recv())
            if message.get('id') == self.sequence:
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message.get('result', {})
    def evaluate(self, expression, gesture=False):
        result = self.call('Runtime.evaluate', expression=expression, returnByValue=True, userGesture=gesture, awaitPromise=True)
        if 'exceptionDetails' in result:
            return {'exception': result['exceptionDetails']}
        return result.get('result', {}).get('value')
    def close(self):
        self.socket.close()

def targets():
    return [t for t in json.load(urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list')) if t['type'] == 'page' and not t['url'].startswith('chrome-extension:')]

def wait_page(url, timeout=45):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        found = [t for t in targets() if t['url'].startswith(url)]
        if found:
            return found[0]
        time.sleep(.3)
    raise RuntimeError(f'No embedded browser reached {url}')

def fixture(codec, filename):
    video = ['-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8'] if codec == 'vp9' else ['-c:v', 'libaom-av1', '-cpu-used', '8', '-row-mt', '1']
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=15', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '3', *video, '-threads', '2', '-c:a', 'libopus', str(fixtures / filename)], check=True)

fixture('vp9', 'vp9.webm')
fixture('av1', 'av1.webm')
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=15', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '4', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-f', 'hls', '-hls_time', '1', '-hls_list_size', '0', str(fixtures / 'hls.m3u8')], check=True)
(fixtures / 'fixture.html').write_text('''<!doctype html><html><head><meta charset="utf-8"><title>Sirb real engine probe</title></head><body>
<div class="ad-banner" id="advert">Local advertising fixture</div><img src="/ads/probe.png">
<video id="vp9" src="vp9.webm" controls muted loop autoplay></video>
<video id="av1" src="av1.webm" controls muted loop autoplay></video>
<video id="hls" src="hls.m3u8" controls muted loop autoplay></video>
<script>window.sirb_document_start=window.__sirbTelemetry===true;window.sirb_cookie_before=document.cookie;window.sirb_storage_before=localStorage.getItem('sirb_probe');document.cookie='sirb_probe=persistent; Max-Age=86400; SameSite=Lax';localStorage.setItem('sirb_probe','persistent');</script>
</body></html>''')
requests = []
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        super().do_GET()
    def log_message(self, fmt, *values):
        pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', args.fixture_port), functools.partial(Handler, directory=str(fixtures)))
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f'http://127.0.0.1:{server.server_port}/fixture.html'
first = next((t for t in targets() if 'youtube.com' not in t['url']), targets()[0])
client = CDP(first)
client.call('Page.navigate', url=url)
time.sleep(8)
result = {'fixture_url': url, 'native_ad_request_canceled': '/ads/probe.png' not in requests, 'requests': requests}
result['chromium'] = client.call('Browser.getVersion')
result['document_start'] = client.evaluate('window.sirb_document_start === true')
result['cookie_before_set']=client.evaluate('window.sirb_cookie_before')
result['storage_before_set']=client.evaluate('window.sirb_storage_before')
result['cosmetic_hidden'] = client.evaluate("getComputedStyle(document.querySelector('#advert')).display === 'none'")
result['media'] = client.evaluate("Array.from(document.querySelectorAll('video')).map(v=>({id:v.id,paused:v.paused,time:v.currentTime,ready:v.readyState,error:v.error&&v.error.code,frames:v.getVideoPlaybackQuality().totalVideoFrames}))")
result['cookie'] = client.evaluate('document.cookie')
result['web_storage'] = client.evaluate("localStorage.getItem('sirb_probe')")
result['codecs'] = client.evaluate("({vp9:MediaSource.isTypeSupported('video/webm;codecs=\"vp9,opus\"'),av1:MediaSource.isTypeSupported('video/webm;codecs=\"av01.0.05M.08,opus\"'),h264aac:MediaSource.isTypeSupported('video/mp4;codecs=\"avc1.42E01E,mp4a.40.2\"')})")
result['fullscreen_request'] = client.evaluate("document.querySelector('#vp9').requestFullscreen().then(()=>true).catch(e=>e.message)", gesture=True)
time.sleep(2)
result['fullscreen_entered'] = client.evaluate('!!document.fullscreenElement')
client.evaluate('document.exitFullscreen()')
result['unmuted_playback'] = client.evaluate("(()=>{const v=document.querySelector('#vp9');v.muted=false;return v.play().then(()=>({muted:v.muted,paused:v.paused})).catch(e=>({error:e.message}));})()", gesture=True)
shot = client.call('Page.captureScreenshot')
(out / 'cef-fixture.png').write_bytes(base64.b64decode(shot['data']))

(out / 'runtime.partial.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
client.evaluate("document.querySelectorAll('video').forEach(v=>v.muted=true)")
# Create five genuine YouTube browser hosts via the same popup dispatcher used
# by window.open. DOM and playback results come from those actual remote pages.
youtube = 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'
existing_youtube = [t for t in targets() if 'youtube.com/watch' in t['url']]
for index in range(max(0, 5-len(existing_youtube))):
    client.evaluate("window.open("+json.dumps(youtube+'&sirb_probe='+str(index))+",'_blank');null",gesture=True)
    time.sleep(2)
time.sleep(25)
result['youtube'] = []
for target in [t for t in targets() if 'youtube.com/watch' in t['url']][:5]:
    page = CDP(target)
    page.evaluate("(()=>{const v=document.querySelector('video');if(!v)return false;v.play().catch(()=>{});return {requested:true,ready:v.readyState};})()", gesture=True)
    time.sleep(3)
    result['youtube'].append(page.evaluate("({url:location.href,title:document.title,video:Array.from(document.querySelectorAll('video')).map(v=>({time:v.currentTime,paused:v.paused,ready:v.readyState,error:v.error&&v.error.code})),ad:!!document.querySelector('.ad-showing'),text:document.body.innerText.slice(0,1500)})"))
    page.close()
client.close()
server.shutdown()
db = sqlite3.connect(str(pathlib.Path(args.profile_data) / 'com.h.sirb' / 'sirb.sqlite'))
snapshot = db.execute('SELECT snapshot,active FROM session').fetchone()
result['session_tab_count'] = len(json.loads(snapshot[0]))
result['active_id'] = snapshot[1]
result['live_cef_pages'] = len(targets())
result['integrity'] = db.execute('PRAGMA integrity_check').fetchone()[0]
db.close()
(out / 'runtime.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
print(json.dumps(result, indent=2, ensure_ascii=False))
assert result['native_ad_request_canceled'], 'Ad request left the engine'
assert result['document_start'] and result['cosmetic_hidden'], 'Document-start filtering failed'
assert result['integrity'] == 'ok', 'SQLite integrity check failed'
assert all(v['frames']>0 and v['error'] is None for v in result['media'] if v['id'] in ['vp9','av1']), 'VP9/AV1 playback failed'
assert result['fullscreen_entered'] and result['unmuted_playback'].get('paused') is False, 'Fullscreen or sound playback failed'
assert len(result['youtube'])==5 and all(v['video'] and any(m['ready']>=2 and m['time']>0 and not m['paused'] for m in v['video']) and not v['ad'] for v in result['youtube']), 'Five real YouTube players did not play without an ad marker'
if args.expect_persistence:
    assert 'sirb_probe=persistent' in result['cookie_before_set'] and result['storage_before_set']=='persistent','Persistent cookie or localStorage was lost'
