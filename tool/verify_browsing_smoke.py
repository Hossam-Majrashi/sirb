#!/usr/bin/env python3
"""Reproducible random public browsing in REAL Sirb, with trusted video input.
Launch an isolated profile and explicitly opt-in loopback CDP first. No sign-in,
permission grants, sandbox overrides, site API spoofing or signed URL retries.
Requires websocket-client. Failures are evidence, not silently passing assertions.
"""
import argparse
import base64
import json
import pathlib
import random
import re
import sqlite3
import time
import urllib.parse
import urllib.request

from verify_game import CDP

PAGES = [
    'https://www.wikipedia.org/',
    'https://docs.flutter.dev/',
    'https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play',
    'https://github.com/flutter/flutter',
    'https://www.python.org/',
    'https://www.w3.org/',
]
YOUTUBE = [
    'https://www.youtube.com/watch?v=b57bk2wt3LE',
    'https://www.youtube.com/watch?v=I5IhWpEXNVE',
    'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    'https://www.youtube.com/watch?v=n1RgvUm3Ki4',
]
WEBM = 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.webm'


def resource_url(value):
    """Do not add signed queries/IP tokens to smoke evidence."""
    try:
        u = urllib.parse.urlsplit(value)
        return urllib.parse.urlunsplit((u.scheme, u.netloc, u.path, '', ''))[:2048]
    except ValueError:
        return '[invalid URL]'


def redact_urls(text):
    return re.sub(r'https?://[^\s<>"\']+', lambda match: resource_url(match.group(0)), text)


class ObservedCDP(CDP):
    def __init__(self, url):
        super().__init__(url)
        self.requests = {}
        self.failures = []
        self.responses = []

    def call(self, method, **params):
        self.sequence += 1
        call_id = self.sequence
        self.socket.send(json.dumps(dict(id=call_id, method=method, params=params)))
        while True:
            message = json.loads(self.socket.recv())
            kind, data = message.get('method'), message.get('params', {})
            if kind == 'Network.requestWillBeSent':
                request = data['request']
                self.requests[data['requestId']] = {
                    'url': resource_url(request['url']), 'method': request['method'],
                    'resourceType': data.get('type'),
                }
                if len(self.requests) > 4096:
                    self.requests.pop(next(iter(self.requests)))
            elif kind == 'Network.loadingFailed' and len(self.failures) < 256:
                self.failures.append({**self.requests.get(data['requestId'], {}),
                    'error': data.get('errorText'), 'canceled': data.get('canceled'),
                    'blockedReason': data.get('blockedReason'),
                    'corsError': data.get('corsErrorStatus')})
            elif kind == 'Network.responseReceived' and len(self.responses) < 512:
                response = data['response']
                if response['status'] >= 400 or '/videoplayback' in response['url']:
                    self.responses.append({'url': resource_url(response['url']),
                        'status': response['status'], 'mimeType': response.get('mimeType'),
                        'resourceType': data.get('type')})
            if message.get('id') == call_id:
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message.get('result', {})


STATE = '''({url:location.href,title:document.title,ready:document.readyState,
 telemetry:!!window.__sirbTelemetry,manualPolicy:!!window.__sirbManualPlayback,
 active:navigator.userActivation.hasBeenActive,
 videos:[...document.querySelectorAll('video')].slice(0,8).map(v=>({
   paused:v.paused,time:v.currentTime,ready:v.readyState,ended:v.ended,
   error:v.error?{code:v.error.code,message:v.error.message}:null,
   decoded:v.getVideoPlaybackQuality().totalVideoFrames})),
 text:document.body?.innerText.slice(0,1600),
 preloadLinks:[...document.querySelectorAll('link[rel=preload]')].slice(0,24)
   .map(l=>({url:l.href.split('?')[0],as:l.as,type:l.type}))})'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=9255)
    parser.add_argument('--database', required=True)
    parser.add_argument('--seed', type=int, default=20261017)
    parser.add_argument('--output', default='build/browsing-smoke-evidence')
    parser.add_argument('--fail-on-playback', action='store_true')
    parser.add_argument('--video-url', action='append', help='Explicit HTTP(S) video URL; repeat for multiple videos')
    parser.add_argument('--page-count', type=int, default=4)
    args = parser.parse_args()
    if not 0 <= args.page_count <= len(PAGES):
        parser.error('--page-count is outside the public-page sample range')
    for url in args.video_url or []:
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme not in ['http', 'https'] or not parsed.hostname or parsed.username or parsed.password:
            parser.error('--video-url requires a credential-free HTTP(S) URL')
    out = pathlib.Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    pages = rng.sample(PAGES, args.page_count)
    videos = args.video_url or (YOUTUBE[:2] + rng.sample(YOUTUBE[2:], 1) + [WEBM])
    rng.shuffle(videos)
    db = sqlite3.connect(args.database)
    with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list') as response:
        target = next(t for t in json.load(response) if t['type'] == 'page')
    page = ObservedCDP(target['webSocketDebuggerUrl'])
    result = {'seed': args.seed, 'engine': page.call('Browser.getVersion'), 'visits': [],
              'limits': 'One Linux host, public logged-out pages, bounded random sample. Not all websites/platforms or codec availability.'}
    try:
        page.call('Network.enable')
        page.call('Page.enable')
        for index, url in enumerate(pages + videos):
            print(f'[{index+1}/{len(pages+videos)}] {url}', flush=True)
            start = db.execute('SELECT COALESCE(MAX(id),0) FROM error_logs').fetchone()[0]
            page.failures.clear()
            page.responses.clear()
            visit = {'url': url, 'videoTest': url in videos}
            try:
                visit['navigation'] = page.call('Page.navigate', url=url)
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    state = page.evaluate(STATE)
                    if isinstance(state, dict) and state.get('ready') == 'complete':
                        break
                    time.sleep(.3)
                time.sleep(5 if url in videos else 2)
                visit['initial'] = page.evaluate(STATE)
                visit['unexpectedAutoplay'] = any(not v['paused'] for v in visit['initial'].get('videos', []))
                if url in videos:
                    # Muting is confined to the explicitly requested test, not a
                    # browser policy. Real input still authorizes the player.
                    page.evaluate("document.querySelectorAll('video').forEach(v=>v.muted=true)")
                    rect = page.evaluate('''(()=>{
                      const b=['.ytp-play-button','.ytp-large-play-button','video']
                        .flatMap(selector=>[...document.querySelectorAll(selector)])
                        .find(e=>{const r=e.getBoundingClientRect();return r.width>1&&r.height>1&&getComputedStyle(e).visibility!=='hidden';});
                      if(!b)return null;
                      b.scrollIntoView({block:'center'});const r=b.getBoundingClientRect();
                      return {x:r.x+r.width/2,y:r.y+r.height/2};})()''')
                    if rect:
                        for kind in ['mousePressed', 'mouseReleased']:
                            page.call('Input.dispatchMouseEvent', type=kind, button='left', clickCount=1, **rect)
                        time.sleep(2)
                        visit['afterClick'] = page.evaluate(STATE)
                        time.sleep(4)
                        visit['afterWait'] = page.evaluate(STATE)
                        before = visit['afterClick'].get('videos', [])
                        after = visit['afterWait'].get('videos', [])
                        visit['playbackAdvanced'] = bool(before and after and
                            (not after[0]['paused'] or after[0]['ended']) and
                            after[0]['time'] > before[0]['time'] + .2 and after[0]['decoded'] > before[0]['decoded'])
                        visit['playbackCompleted'] = bool(after and after[0]['ended'])
                        if visit['playbackAdvanced'] and not visit['playbackCompleted']:
                            # Trusted native/custom player button tests manual
                            # pause. Retain evidence before leaving the page.
                            for kind in ['mousePressed', 'mouseReleased']:
                                page.call('Input.dispatchMouseEvent', type=kind, button='left', clickCount=1, **rect)
                            time.sleep(.4)
                            visit['afterPause'] = page.evaluate(STATE)
                            visit['pauseRespected'] = bool(visit['afterPause'].get('videos') and visit['afterPause']['videos'][0]['paused'])
                    else:
                        visit['playbackAdvanced'] = False
                        visit['playbackBlocker'] = 'No player control/video in the loaded document'
                # Drain diagnostic events and keep a screenshot of this result.
                page.evaluate('document.readyState')
                (out/f'{index:02d}.png').write_bytes(base64.b64decode(page.call('Page.captureScreenshot')['data']))
                rows = db.execute('SELECT type,message,details FROM error_logs WHERE id>? ORDER BY id', (start,)).fetchall()
                records = []
                for typ, message, details in rows:
                    try:
                        data = json.loads(details or '{}')
                        if not isinstance(data, dict):
                            data = {'details': resource_url(details or '')}
                    except json.JSONDecodeError:
                        data = {'details': resource_url(details or '')}
                    for key in ['source', 'resource', 'frameUrl', 'details']:
                        if isinstance(data.get(key), str) and '://' in data[key]:
                            data[key] = redact_urls(data[key])
                    records.append({'type': typ, 'message': redact_urls(message[:4096]), 'details': data})
                visit.update(records=records, networkFailures=list(page.failures), responses=list(page.responses))
            except Exception as error:
                visit['testError'] = str(error)
            result['visits'].append(visit)
            (out/'results.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
            print(json.dumps({'loaded': visit.get('initial', {}).get('telemetry'),
                              'playbackAdvanced': visit.get('playbackAdvanced'),
                              'testError': visit.get('testError')}, ensure_ascii=False), flush=True)
        failed = [v['url'] for v in result['visits'] if v.get('videoTest') and not v.get('playbackAdvanced')]
        issues = [v['url'] for v in result['visits'] if v.get('testError') or
                  not v.get('initial', {}).get('telemetry') or v.get('unexpectedAutoplay') or
                  v.get('navigation', {}).get('errorText') or v.get('pauseRespected') is False]
        print(json.dumps({'pages': len(pages), 'videos': len(videos), 'failedPlayback': failed,
                          'policyOrNavigationIssues': issues, 'output': str(out)}, indent=2))
        if args.fail_on_playback and (failed or issues):
            raise RuntimeError('Browsing/playback smoke failures; inspect recorded evidence')
    finally:
        page.close()
        db.close()


if __name__ == '__main__':
    main()
