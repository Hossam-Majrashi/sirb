#!/usr/bin/env python3
"""Measure the game in Sirb's embedded CEF (not a separate browser).
Start an isolated Sirb with SIRB_CEF_SWITCHES=remote-debugging-port=9227.
Requires websocket-client. --start explicitly consents to the site's large download.
CDP should only be enabled on loopback for local testing, never in production.
"""
import argparse
import base64
import json
import pathlib
import time
import urllib.request

import websocket


class CDP:
    def __init__(self, url):
        self.socket = websocket.create_connection(url, timeout=90, suppress_origin=True)
        self.sequence = 0
        self.accept_beforeunload = False

    def call(self, method, **params):
        self.sequence += 1
        call_id = self.sequence
        self.socket.send(json.dumps(dict(id=call_id, method=method, params=params)))
        while True:
            message = json.loads(self.socket.recv())
            if (self.accept_beforeunload and message.get('method') == 'Page.javascriptDialogOpening'
                    and message.get('params', {}).get('type') == 'beforeunload'):
                self.sequence += 1
                self.socket.send(json.dumps(dict(id=self.sequence,
                    method='Page.handleJavaScriptDialog', params={'accept': True})))
            if message.get('id') == call_id:
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message.get('result', {})

    def evaluate(self, expression, gesture=False):
        result = self.call('Runtime.evaluate', expression=expression, returnByValue=True,
                           awaitPromise=True, userGesture=gesture)
        if 'exceptionDetails' in result:
            return {'exception': result['exceptionDetails']}
        return result.get('result', {}).get('value')

    def close(self):
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=9227)
    parser.add_argument('--url', default='https://vel.gg/bo1z/kino?mode=single&guns=classic')
    parser.add_argument('--start', action='store_true')
    parser.add_argument('--release-mouse', action='store_true',
                        help='Release real pointer capture after saving gameplay evidence')
    parser.add_argument('--wait', type=int, default=15)
    parser.add_argument('--sample-seconds', type=int, default=10,
                        help='Sample the game engine Present ring, not page rAF or display FPS')
    parser.add_argument('--output', default='build/game-evidence')
    args = parser.parse_args()
    if not 1 <= args.sample_seconds <= 120:
        parser.error('--sample-seconds must be between 1 and 120')
    endpoint = f'http://127.0.0.1:{args.port}'
    def get(path):
        with urllib.request.urlopen(endpoint + path, timeout=10) as response:
            return json.load(response)
    pages = [t for t in get('/json/list') if t['type'] == 'page']
    if not pages:
        raise RuntimeError('Open a web tab in Sirb first')
    target = next((t for t in pages if t['url'] == args.url), pages[0])
    page = CDP(target['webSocketDebuggerUrl'])
    browser = CDP(get('/json/version')['webSocketDebuggerUrl'])
    try:
        result = {'url': args.url, 'chromium': browser.call('Browser.getVersion'),
                  'gpu': browser.call('SystemInfo.getInfo')['gpu']}
        if target['url'] != args.url:
            page.call('Page.navigate', url=args.url)
            time.sleep(10)
        if args.start:
            # Native Chromium windows reject capture while unfocused. This
            # foregrounds the real host; it does not grant/override permissions.
            page.call('Page.bringToFront')
            result['start'] = page.evaluate("""(()=>{const b=document.querySelector('#play');
                if(!b||b.disabled)return {clicked:false,text:b?.textContent};
                b.click();return {clicked:true,text:b.textContent};})()""", gesture=True)
        time.sleep(args.wait)
        result['page'] = page.evaluate("""({title:document.title,url:location.href,
            isolated:crossOriginIsolated,sharedArrayBuffer:typeof SharedArrayBuffer==='function',
            webgpu:!!navigator.gpu,canvas:Array.from(document.querySelectorAll('canvas')).map(c=>({width:c.width,height:c.height})),
            screen:document.body.dataset.screen,status:document.querySelector('#status')?.textContent,
            error:document.querySelector('#error-message')?.textContent,
            play:document.querySelector('#play')?.textContent,
            pointerLocked:!!document.pointerLockElement,
            audio:window.__sirbAudioDiagnostics?.()??null,
            game:window.five?{screen:five.screen,errors:five.errors,timings:five.timings,
                renderer:five.renderer,rendererRequested:five.rendererRequested,
                consoleErrors:five.consoleErrors,interactive:five.interactive,
                audioFrames:five.audioFrames,audioDiscardedFrames:five.audioDiscardedFrames,
                audioSnapshot:five.engine?.audioSnapshot?.(),
                memory:five.engine?.telemetryMemory?.()}:null,
            text:document.body.innerText.slice(0,2500)})""")
        # The site exposes an independent cursor into its engine Present ring.
        # This observes engine output only, NOT physical display presentation.
        result['enginePresent'] = page.evaluate("""(async()=>{
            const engine=window.five?.engine;
            if(typeof engine?.presentReader!=='function')
                return {available:false,reason:'No engine Present reader'};
            const read=engine.presentReader(), gaps=[];
            read(); // Discard any frames already in the ring before our sample.
            const start=performance.now(), initialScreen=window.five?.screen;
            let lost=0,nonPlayingSamples=0,hiddenSamples=0,unlockedSamples=0,unfocusedSamples=0;
            do {
                await new Promise(r=>setTimeout(r,250));
                const frames=read();lost+=frames?.lost??0;
                for(const gap of frames?.intervals??[])
                    if(Number.isFinite(gap)&&gap>0)gaps.push(gap);
                if(window.five?.screen!=='playing')nonPlayingSamples++;
                if(document.visibilityState!=='visible')hiddenSamples++;
                if(!document.pointerLockElement)unlockedSamples++;
                if(!document.hasFocus())unfocusedSamples++;
            } while(performance.now()-start<SAMPLE_MS);
            const elapsedMs=performance.now()-start;
            gaps.sort((a,b)=>a-b);
            const quantile=q=>gaps.length?gaps[Math.min(gaps.length-1,Math.floor(gaps.length*q))]:null;
            return {available:true,metric:'engine Present calls (not display FPS)',
                initialScreen,finalScreen:window.five?.screen,elapsedMs,
                frames:gaps.length,fps:gaps.length*1000/elapsedMs,
                p50Ms:quantile(.5),p95Ms:quantile(.95),p99Ms:quantile(.99),
                maxMs:gaps.at(-1)??null,over33:gaps.filter(g=>g>33).length,
                over100:gaps.filter(g=>g>100).length,lost,nonPlayingSamples,hiddenSamples,
                unlockedSamples,unfocusedSamples};
        })()""".replace('SAMPLE_MS', str(args.sample_seconds * 1000)))
        # These are page scheduling intervals, NOT game-rendered or presented FPS.
        result['raf'] = page.evaluate("""new Promise(resolve=>{
            const gaps=[];let last,start,done=false;
            const finish=()=>{if(done)return;done=true;gaps.sort((a,b)=>a-b);
                resolve({samples:gaps.length,medianMs:gaps[Math.floor(gaps.length*.5)]??null,
                    p95Ms:gaps[Math.floor(gaps.length*.95)]??null});};
            const timeout=setTimeout(finish,6000);
            const tick=t=>{if(done)return;if(start===undefined)start=t;
                if(last!==undefined)gaps.push(t-last);last=t;
                if(t-start>=3000){clearTimeout(timeout);finish();}else requestAnimationFrame(tick);};
            requestAnimationFrame(tick);
        })""")
        out = pathlib.Path(args.output)
        out.mkdir(parents=True, exist_ok=True)
        (out / 'cef-game.png').write_bytes(base64.b64decode(page.call('Page.captureScreenshot')['data']))
        if args.release_mouse:
            result['mouseReleased'] = page.evaluate("""new Promise(resolve=>{
                document.exitPointerLock();setTimeout(()=>resolve(!document.pointerLockElement),100);
            })""")
        (out / 'game.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
        print(json.dumps(result, indent=2, ensure_ascii=False))
    finally:
        page.close()
        browser.close()


if __name__ == '__main__':
    main()
