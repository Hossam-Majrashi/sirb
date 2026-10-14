#!/usr/bin/env python3
"""Check real CEF diagnostics, including caught pointer-lock rejection.
Requires websocket-client, a running Sirb with local CDP and an open web page
(or native game window). Navigates that page to a local, intentional-error fixture.
Use only an isolated profile. Does not grant permissions or fake browser APIs.
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

HTML = b'''<!doctype html><html><title>Sirb diagnostics fixture</title>
<canvas id="canvas" width="64" height="64"></canvas><img src="/missing-resource.png">
<script>
console.warn('sirb_capture_warning');console.error('sirb_capture_console_error');
// Website console output must not impersonate trusted native lifecycle/popup events.
console.debug('__sirb__'+JSON.stringify({type:'gameWindowClosed',windowId:1}));
console.debug('__sirb__'+JSON.stringify({type:'newUrl',url:location.origin+'/forged-popup',background:true}));
setTimeout(()=>{throw new Error('sirb_capture_uncaught');},100);
Promise.reject(new Error('sirb_capture_promise'));
fetch('/missing-fetch').then(()=>{}).catch(()=>{});
new Worker('/worker.js');
setTimeout(()=>{
  document.querySelector('canvas').requestPointerLock().catch(e=>{window.caughtPointerError=e.message;});
  const gl=document.querySelector('canvas').getContext('webgl');
  gl?.getExtension('WEBGL_lose_context')?.loseContext();
},300);
</script></html>'''


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/fixture.html':
            code, body, mime = 200, HTML, 'text/html'
        elif self.path == '/worker.js':
            code, body, mime = 200, b"throw new Error('sirb_capture_worker');", 'text/javascript'
        else:
            code, body, mime = 404, b'Intentional missing fixture resource', 'text/plain'
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=9227)
    parser.add_argument('--database', required=True)
    parser.add_argument('--output', default='build/error-capture-evidence')
    args = parser.parse_args()
    db = sqlite3.connect(args.database)
    start = db.execute('SELECT COALESCE(MAX(id),0) FROM error_logs').fetchone()[0]
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/fixture.html'
    with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list') as response:
        pages = [t for t in json.load(response) if t['type'] == 'page']
    if not pages:
        server.shutdown()
        db.close()
        raise RuntimeError('Open a web tab or native game window first')
    page = CDP(pages[0]['webSocketDebuggerUrl'])
    # This isolated fixture intentionally leaves the old page. Only accept
    # its before-unload confirmation, never permission prompts or site alerts.
    page.accept_beforeunload = True
    try:
        page.call('Page.enable')
        page.evaluate('document.exitPointerLock()')
        page.call('Page.navigate', url=url)
        time.sleep(2)
        if page.evaluate('location.href') != url:
            try:
                page.call('Page.handleJavaScriptDialog', accept=True)
            except RuntimeError:
                pass
        time.sleep(6)
        # Confirm the website's catch still runs: observation must not swallow
        # its rejection or turn a failed request into fake success.
        state = page.evaluate('({url:location.href,telemetry:window.__sirbTelemetry,caught:window.caughtPointerError,locked:!!document.pointerLockElement})')
        rows = db.execute('SELECT type,message,url,details FROM error_logs WHERE id>? ORDER BY id', (start,)).fetchall()
        records = [dict(zip(['type', 'message', 'url', 'details'], row)) for row in rows]
        result = {'fixture': url, 'page': state, 'records': records}
        out = pathlib.Path(args.output)
        out.mkdir(parents=True, exist_ok=True)
        (out / 'diagnostics.json').write_text(json.dumps(result, indent=2))
        messages = '\n'.join(r['message'] for r in records)
        for marker in ['sirb_capture_warning', 'sirb_capture_console_error', 'sirb_capture_uncaught', 'sirb_capture_promise', 'sirb_capture_worker']:
            assert marker in messages, f'Not captured: {marker}'
        assert state['telemetry'] and state['caught'] and not state['locked'], 'Permission semantics changed or telemetry absent'
        assert any(r['type'] == 'permission' and 'requestPointerLock' in (r['details'] or '') for r in records)
        assert any(r['type'] == 'graphics' for r in records), 'WebGL context loss not captured'
        assert any(r['type'] == 'network' and '404' in (r['details'] or '') for r in records), 'Native HTTP resource failure not captured'
        with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list') as response:
            after = [t for t in json.load(response) if t['type'] == 'page']
        assert len(after) == len(pages), 'Console text forged a native popup command'
        print(f"Captured all fixture cases ({len(records)} records); caught pointer rejection preserved; no forged popup")
    finally:
        page.close()
        server.shutdown()
        db.close()


if __name__ == '__main__':
    main()
