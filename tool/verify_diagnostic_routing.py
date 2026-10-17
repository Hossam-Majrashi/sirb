#!/usr/bin/env python3
"""Actual Sirb/CEF: ResizeObserver capture, ad cancellation vs real HTTP errors.
Run only with an isolated profile and opt-in loopback CDP. --shield-off expects
an instance launched with blocking disabled. Requires websocket-client.
"""
import argparse
import http.server
import json
import pathlib
import sqlite3
import threading
import time
import urllib.request

from verify_game import CDP

HTML = b'''<!doctype html><title>Sirb diagnostic routing fixture</title>
<link rel="preload" href="/unused.txt" as="fetch" crossorigin="anonymous">
<div id="box" style="width:100px;height:100px"></div>
<script src="/ads/missing.js"></script><script src="/missing.js"></script>
<script>
window.loopErrors=0;window.resizeDeliveries=0;
addEventListener('error',event=>{if(event.message==='ResizeObserver loop completed with undelivered notifications.')loopErrors++;});
const box=document.querySelector('#box');
const observer=new ResizeObserver(()=>{
  if(++resizeDeliveries<=2)box.style.width=(box.getBoundingClientRect().width+1)+'px';
  else observer.disconnect();
});observer.observe(box);
fetch('/truncated.txt').then(r=>r.text()).catch(()=>{});
const preloadWarning="The resource https://i.ytimg.com/generate_204 was preloaded using link preload but not used within a few seconds from the window's load event. Please make sure it has an appropriate `as` value and it is preloaded intentionally.";
console.warn(preloadWarning);console.warn(preloadWarning);
console.warn('No available adapters.');
console.error('sirb_real_graphics_failure_not_hidden');
const utility=document.createElement('iframe');utility.sandbox='allow-same-origin';
document.body.append(utility);
const script=utility.contentDocument.createElement('script');script.textContent='window.sandboxEscape=true';
utility.contentDocument.body.append(script);
window.sandboxUtility=utility;
</script>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=9251)
    parser.add_argument('--database', required=True)
    parser.add_argument('--shield-off', action='store_true')
    parser.add_argument('--output', default='build/diagnostic-routing-evidence')
    args = parser.parse_args()
    db = sqlite3.connect(args.database)
    start = db.execute('SELECT COALESCE(MAX(id),0) FROM error_logs').fetchone()[0]
    requests = []

    class Fixture(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            requests.append(self.path)
            if self.path == '/fixture.html':
                code, body, mime = 200, HTML, 'text/html'
            else:
                code, body, mime = 404, b'Intentional fixture failure', 'text/plain'
            if self.path == '/unused.txt':
                code, body, mime = 200, b'Unused but successfully downloaded preload', 'text/plain'
            if self.path == '/truncated.txt':
                code, body, mime = 200, b'partial-body', 'text/plain'
            self.send_response(code)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(body)+100 if self.path == '/truncated.txt' else len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    page = None
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list') as response:
            target = next(t for t in json.load(response) if t['type'] == 'page')
        page = CDP(target['webSocketDebuggerUrl'])
        url = f'http://127.0.0.1:{server.server_port}/fixture.html'
        page.call('Page.navigate', url=url)
        time.sleep(7)
        state = page.evaluate('''({telemetry:!!window.__sirbTelemetry,shield:window.__sirbBlocking,
          loopErrors,resizeDeliveries,sandbox:sandboxUtility.sandbox.value,
          escaped:!!sandboxUtility.contentWindow.sandboxEscape,
          preload:document.querySelector('link[rel="preload"]').getAttribute('as')})''')
        rows = db.execute('SELECT type,message,url,details FROM error_logs WHERE id>? ORDER BY id', (start,)).fetchall()
        records = [dict(zip(['type', 'message', 'url', 'details'], row)) for row in rows]
        resize = [r for r in records if r['message'] == 'ResizeObserver loop completed with undelivered notifications.']
        assert state['telemetry'] and state['shield'] == (not args.shield_off), state
        assert state['loopErrors'] > 0, 'Real ResizeObserver loop was not exercised'
        assert len(resize) == state['loopErrors'], (state, resize)
        assert all('resizeObserverDeferredNotifications' in r['details'] for r in resize)
        assert state['sandbox'] == 'allow-same-origin' and not state['escaped'], 'Frame script sandbox was weakened'
        assert any(r['type'] == 'permission' and 'frameSandboxBlockedScript' in (r['details'] or '') for r in records)
        assert any(r['type'] == 'graphics' and 'webgpuAdapterUnavailable' in (r['details'] or '') for r in records)
        assert any(r['message'] == 'sirb_real_graphics_failure_not_hidden' for r in records)
        hints = [r for r in records if r['type'] == 'performance']
        assert len(hints) == 2 and all('unusedPreload' in r['details'] for r in hints), hints
        assert state['preload'] == 'fetch', 'Site preload policy was changed to suppress a warning'
        assert any('/unused.txt' in r['details'] for r in hints), hints
        transfers = [r for r in records if '/truncated.txt' in (r['details'] or '')]
        assert any(r['type'] == 'network' and 'responseBodyTransferFailed' in r['details'] and
                   'requestStatus' in r['details'] and 'receivedBytes' in r['details'] for r in transfers), transfers
        assert any(r['type'] == 'network' and '/missing.js' in (r['details'] or '') and '404' in r['details'] for r in records)
        ad_failures = [r for r in records if '/ads/missing.js' in (r['details'] or '')]
        if args.shield_off:
            assert '/ads/missing.js' in requests, requests
            assert any(r['type'] == 'network' and '404' in r['details'] for r in ad_failures), ad_failures
            assert not any(r['type'] == 'ad' for r in ad_failures), ad_failures
        else:
            assert '/ads/missing.js' not in requests, 'Blocked request reached the server'
            # Chromium may issue both speculative-parser and parser requests;
            # retain each native cancellation, but not an extra DOM network fault.
            assert ad_failures and all(r['type'] == 'ad' for r in ad_failures), ad_failures
        out = pathlib.Path(args.output)
        out.mkdir(parents=True, exist_ok=True)
        result = {'result': 'PASS', 'state': state, 'requests': requests, 'records': records,
                  'limits': 'Controlled fixtures; GPU console warning is intentional, not a hardware availability test.'}
        (out/'diagnostics.json').write_text(json.dumps(result, indent=2))
        print(json.dumps({'result': 'PASS', 'state': state, 'resizeRecords': len(resize),
                          'adRelatedRecords': ad_failures, 'totalRecords': len(records)}, indent=2))
    finally:
        if page:
            page.close()
        server.shutdown()
        db.close()


if __name__ == '__main__':
    main()
