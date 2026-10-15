#!/usr/bin/env python3
"""Verify REAL MP4/MSE decoding in Sirb's embedded CEF, not system Chromium.

Start Sirb with an isolated profile and opt-in loopback CDP, then:
  python3 tool/verify_stream_codecs.py --port 9241 --require-h264-aac
Requires ffmpeg and websocket-client. Writes measured evidence; does not install
codecs, alter browser APIs, grant permissions or claim live Twitch/Kick success.
Without --require-h264-aac this is an observational diagnostic, not a release gate.
"""
import argparse
import functools
import http.server
import json
import pathlib
import subprocess
import threading
import time
import urllib.request

from verify_game import CDP


PAGE = '''<!doctype html><html><head><meta charset="utf-8"><title>Sirb codec probe</title></head>
<body><video id="control" controls muted loop src="/control.webm"></video>
<video id="mp4" controls muted loop src="/clip.mp4"></video>
<video id="mse" controls muted></video>
<script>
window.mseResult={state:'not-started'};
window.startMse=async()=>{
  const type='video/mp4;codecs="avc1.42C01E,mp4a.40.2"';
  if(!window.MediaSource?.isTypeSupported(type)){
    mseResult={state:'unsupported'};return;
  }
  const media=new MediaSource(),video=document.querySelector('#mse');
  video.src=URL.createObjectURL(media);
  media.addEventListener('sourceopen',async()=>{
    try{
      const buffer=media.addSourceBuffer(type);
      buffer.addEventListener('error',()=>mseResult={state:'buffer-error'});
      buffer.addEventListener('updateend',()=>{
        if(media.readyState==='open')media.endOfStream();
        mseResult={state:'appended'};
        video.play().catch(error=>mseResult={state:'play-rejected',error:String(error)});
      },{once:true});
      buffer.appendBuffer(await (await fetch('/clip.mp4')).arrayBuffer());
    }catch(error){mseResult={state:'exception',error:String(error)};}
  },{once:true});
};
</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=9241)
    parser.add_argument('--output', default='build/stream-codec-evidence')
    parser.add_argument('--require-h264-aac', action='store_true')
    args = parser.parse_args()
    output = pathlib.Path(args.output).resolve()
    fixtures = output/'fixtures'
    fixtures.mkdir(parents=True, exist_ok=True)
    base = ['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i',
            'testsrc2=size=320x180:rate=15', '-f', 'lavfi', '-i',
            'anullsrc=r=48000:cl=stereo', '-t', '5', '-threads', '2']
    subprocess.run(base+['-c:v', 'libx264', '-profile:v', 'baseline', '-level:v', '3.0',
                        '-pix_fmt', 'yuv420p', '-g', '15', '-c:a', 'aac',
                        '-movflags', 'frag_keyframe+empty_moov+default_base_moof',
                        str(fixtures/'clip.mp4')], check=True)
    subprocess.run(base+['-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8',
                        '-c:a', 'libopus', str(fixtures/'control.webm')], check=True)
    (fixtures/'index.html').write_text(PAGE)
    requests = []

    class Handler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            super().do_GET()

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
        functools.partial(Handler, directory=str(fixtures)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    page = None
    original = None
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list', timeout=10) as response:
            targets = json.load(response)
        target = next((t for t in targets if t['type']=='page' and
                       not t['url'].startswith('chrome-extension:')), None)
        if not target:
            raise RuntimeError('Open one HTTP(S) tab in the isolated Sirb instance first')
        page = CDP(target['webSocketDebuggerUrl'])
        original = target['url']
        engine = page.call('Browser.getVersion')
        page.call('Page.navigate', url=f'http://127.0.0.1:{server.server_port}/index.html')
        deadline = time.monotonic()+20
        while time.monotonic()<deadline:
            if page.evaluate("typeof window.startMse==='function'"):
                break
            time.sleep(.1)
        else:
            raise RuntimeError('Local codec fixture failed to load')
        configuration = page.evaluate('({sirbDocumentStart:window.__sirbTelemetry===true,blocking:window.__sirbBlocking,focusLoading:window.__sirbFocusLoading,speculative:window.__sirbSpeculative})')
        if configuration.get('sirbDocumentStart') is not True:
            raise RuntimeError('No Sirb document-start policy found; refusing to verify a different browser')
        capabilities = page.evaluate('''({
          h264:!!window.MediaSource?.isTypeSupported('video/mp4;codecs="avc1.42C01E"'),
          aac:!!window.MediaSource?.isTypeSupported('audio/mp4;codecs="mp4a.40.2"'),
          h264aac:!!window.MediaSource?.isTypeSupported('video/mp4;codecs="avc1.42C01E,mp4a.40.2"'),
          vp9opus:!!window.MediaSource?.isTypeSupported('video/webm;codecs="vp9,opus"'),
          nativeMp4:document.createElement('video').canPlayType('video/mp4;codecs="avc1.42C01E,mp4a.40.2"'),
          nativeHls:document.createElement('video').canPlayType('application/vnd.apple.mpegurl')
        })''')
        play = page.evaluate('''Promise.all(['control','mp4'].map(async id=>{
          const video=document.getElementById(id);
          try{await video.play();return {id,accepted:true};}
          catch(error){return {id,accepted:false,error:String(error)};}
        }))''', gesture=True)
        page.evaluate('window.startMse()')
        snapshot = '''Array.from(document.querySelectorAll('video')).map(v=>({
          id:v.id,paused:v.paused,time:v.currentTime,ready:v.readyState,
          error:v.error?{code:v.error.code,message:v.error.message}:null,
          frames:v.getVideoPlaybackQuality().totalVideoFrames
        }))'''
        time.sleep(1)
        before = page.evaluate(snapshot)
        time.sleep(1)
        after = page.evaluate(snapshot)
        advanced = {v['id']: v['time']>next(p['time'] for p in before if p['id']==v['id'])+.1
                    and v['frames']>0 and not v['paused'] and v['error'] is None for v in after}
        passed = all(capabilities.get(k) is True for k in ['h264','aac','h264aac']) and all(advanced.values())
        result = {'engine': engine, 'configuration': configuration, 'capabilities': capabilities, 'playRequests': play,
                  'before': before, 'after': after, 'advanced': advanced,
                  'mse': page.evaluate('window.mseResult'), 'fixtureRequests': requests,
                  'h264AacPlaybackVerified': passed,
                  'limits': 'Local native MP4 and MSE test; not native HLS, DRM, live Twitch/Kick, region/account availability or an ad-removal guarantee.'}
        (output/'result.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
        if not advanced.get('control'):
            raise RuntimeError('VP9/Opus control did not play; codec test environment is inconclusive')
        if args.require_h264_aac and not passed:
            raise RuntimeError('RELEASE GATE FAILED: the actual CEF engine did not decode H.264/AAC via MP4 and MSE')
    finally:
        if page:
            try:
                if original:
                    page.call('Page.navigate', url=original)
            finally:
                page.close()
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
