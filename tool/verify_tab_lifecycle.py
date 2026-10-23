#!/usr/bin/env python3
"""Real Linux/X11 idle-tab wake, Flutter texture, reload and crash-retry probe.
Uses one isolated Sirb window, local fixtures and opt-in loopback CDP. Default
idle threshold is FIVE REAL MINUTES, not an accelerated clock. Requires
websocket-client, XTest and ImageMagick. Closes only its own test process at end.
"""
import argparse
import ctypes as C
import http.server
import json
import os
from pathlib import Path
import signal
import shutil
import sqlite3
import subprocess
import tempfile
import threading
import time
import urllib.request

from verify_clipboard import XInput, wait
from verify_game import CDP


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', default='build/linux/x64/release/bundle/sirb')
    parser.add_argument('--port', type=int, default=9269)
    parser.add_argument('--idle-minutes', type=int, default=5)
    parser.add_argument('--crash-only', action='store_true', help='Skip idle retirement; verify renderer retry only')
    parser.add_argument('--minimize-idle', action='store_true', help='Minimize only the test window while waiting')
    parser.add_argument('--output', default='build/tab-lifecycle-evidence')
    args = parser.parse_args()
    if args.idle_minutes < 1:
        parser.error('--idle-minutes must be positive')
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    visits = {'/home': 0, '/background': 0}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in visits:
                self.send_error(404)
                return
            visits[self.path] += 1
            background = self.path == '/background'
            color = '#194477' if background else '#3b5430'
            body = f'''<!doctype html><meta charset="utf-8"><title>Sirb {'background' if background else 'home'} fixture</title>
<style>html,body{{margin:0;min-height:100%;background:{color};color:white}}
a{{display:block;padding:40px;color:white}}</style>
<h1>Local idle lifecycle fixture</h1>
{'' if background else '<a id="open" href="/background" target="_blank">Open background fixture</a>'}
<p id="visit">Visit {visits[self.path]}</p><script>window.visit={visits[self.path]};</script>'''
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(body.encode())
        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    home_url = f'http://127.0.0.1:{server.server_port}/home'
    background_url = home_url.replace('/home', '/background')
    with tempfile.TemporaryDirectory(prefix='sirb-tab-lifecycle-') as profile:
        data = Path(profile) / 'com.h.sirb'
        data.mkdir()
        (data / 'shared_preferences.json').write_text(json.dumps({
            'flutter.onboarding_done': True, 'flutter.startup': 'new',
            'flutter.idle_minutes': args.idle_minutes, 'flutter.live_limit': 20}))
        env = {**os.environ, 'XDG_DATA_HOME': profile, 'XDG_CONFIG_HOME': profile,
            'GDK_BACKEND': 'x11', 'SIRB_CEF_SWITCHES': f'remote-debugging-port={args.port}'}
        with (out / 'sirb.log').open('w') as log:
            process = subprocess.Popen([str(Path(args.binary).resolve()), home_url], env=env,
                stdout=log, stderr=log, start_new_session=True)
            clients = []
            native = None
            try:
                def targets():
                    with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list', timeout=3) as response:
                        return json.load(response)

                def target_for(url):
                    try:
                        return next((t for t in targets() if t['type'] == 'page' and t['url'] == url), None)
                    except OSError:
                        return None

                def connect(target):
                    page = CDP(target['webSocketDebuggerUrl'])
                    clients.append(page)
                    wait(lambda: page.evaluate('document.readyState') == 'complete', 'fixture finished loading')
                    return page

                def screenshot(name, blue=False):
                    path = out / (name + '.png')
                    subprocess.run(['import', '-window', hex(native.window), str(path)], check=True)
                    if blue:
                        # The bottom-right viewport is all fixture background.
                        pixel = subprocess.check_output(['magick' if shutil.which('magick') else 'convert', str(path), '-gravity', 'SouthEast',
                            '-crop', '1x1+40+40', '+repage', '-depth', '8', 'rgb:-'])
                        assert pixel == bytes([25, 68, 119]), f'Flutter texture is not the loaded fixture: {list(pixel)}'

                home_target = wait(lambda: target_for(home_url), 'home target')
                home = connect(home_target)
                native = XInput(process.pid)
                result = {'engine': home.call('Browser.getVersion'), 'idleMinutes': args.idle_minutes,
                    'platform': 'Linux X11', 'checks': {}}
                # Give the CEF surface keyboard ownership before holding Ctrl.
                native.click_content(home, 100, 25)
                control = native.x.XKeysymToKeycode(native.d, native.x.XStringToKeysym(b'Control_L'))
                native.xt.XTestFakeKeyEvent(native.d, control, 1, 0)
                native.x.XFlush(native.d)
                try:
                    native.click_element(home, '#open')
                finally:
                    native.xt.XTestFakeKeyEvent(native.d, control, 0, 0)
                    native.x.XFlush(native.d)
                background = wait(lambda: target_for(background_url), 'background tab created')
                assert target_for(home_url), 'fixture link navigated the opener instead of creating a tab'
                home.evaluate("document.querySelector('#open')?.remove()")
                native.key('2', ctrl=True)
                def home_is_active():
                    with sqlite3.connect(data / 'sirb.sqlite') as db:
                        snapshot, active = db.execute('SELECT snapshot, active FROM session WHERE id=1').fetchone()
                        return any(t['id'] == active and t['url'] == home_url for t in json.loads(snapshot))
                wait(home_is_active, 'foreground fixture was not selected')
                screenshot('before-idle')
                start = time.monotonic()
                if not args.crash_only:
                    if args.minimize_idle:
                        native.x.XIconifyWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int]
                        native.x.XIconifyWindow(native.d, native.window, 0)
                        native.x.XFlush(native.d)
                    print(f'Waiting for real {args.idle_minutes}-minute idle retirement in one isolated test window...', flush=True)
                    def idle_retired():
                        assert process.poll() is None, f'Isolated Sirb exited during idle: {process.returncode}; not a successful retirement'
                        return not any(t['url'] == background_url for t in targets())
                    wait(idle_retired, 'background host was not retired',
                        timeout=args.idle_minutes * 60 + 35)
                elapsed = time.monotonic() - start
                if not args.crash_only:
                    assert elapsed >= args.idle_minutes * 60 - 5, 'host disappeared before configured idle threshold'
                assert target_for(home_url), 'foreground host must remain alive'
                with sqlite3.connect(data / 'sirb.sqlite') as db:
                    assert db.execute("SELECT COUNT(*) FROM error_logs WHERE type='crash'").fetchone()[0] == 0
                result['idleObservedSeconds'] = None if args.crash_only else round(elapsed, 3)
                result['checks']['idle_host_retired_without_crash'] = None if args.crash_only else True
                # Reacquire only this test window: the user may have focused
                # another application during the five-minute idle interval.
                if args.minimize_idle and not args.crash_only:
                    native.x.XMapRaised.argtypes = [C.c_void_p, C.c_ulong]
                    native.x.XMapRaised(native.d, native.window)
                    native.x.XFlush(native.d)
                    time.sleep(.5)
                native.x.XRaiseWindow(native.d, native.window)
                native.x.XSetInputFocus(native.d, native.window, 1, 0)
                native.x.XFlush(native.d)
                # Startup has one sirb:new tab, then home and the ctrl-clicked child.
                native.key('3', ctrl=True)
                awake = wait(lambda: target_for(background_url), 'sleeping tab did not recreate a host')
                if not args.crash_only:
                    assert awake['id'] != background['id'], 'wake reused a retired host'
                page = connect(awake)
                if not args.crash_only:
                    assert page.evaluate('visit') >= 2
                time.sleep(1)
                screenshot('after-wake', blue=True)
                result['checks']['wake_navigation_and_flutter_texture'] = None if args.crash_only else True
                old_visit = page.evaluate('visit')
                native.key('r', ctrl=True)
                wait(lambda: page.evaluate('visit') > old_visit, 'normal reload after wake failed')
                time.sleep(.5)
                screenshot('after-reload', blue=True)
                result['checks']['reload_after_wake'] = None if args.crash_only else True
                (out / 'idle-progress.json').write_text(json.dumps(result, indent=2))
                print('Idle skipped; testing renderer retry.' if args.crash_only else
                    f'Idle/wake/reload passed after {elapsed:.3f}s; testing renderer retry.', flush=True)
                # Kill only renderer descendants of this disposable Sirb,
                # never Sirb itself or any user browser. CEF sandboxing can
                # deny /proc/environ; use browser CDP roles + ancestry instead.
                with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/version', timeout=3) as response:
                    inspector = CDP(json.load(response)['webSocketDebuggerUrl'])
                clients.append(inspector)
                processes = inspector.call('SystemInfo.getProcessInfo')['processInfo']
                def owned_renderer(pid):
                    ancestor = pid
                    seen = set()
                    while ancestor > 1 and ancestor not in seen:
                        if ancestor == process.pid:
                            return True
                        seen.add(ancestor)
                        try:
                            stat = Path(f'/proc/{ancestor}/stat').read_text()
                            ancestor = int(stat[stat.rfind(')') + 2:].split()[1])
                        except (OSError, ValueError):
                            return False
                    return False
                renderer_pids = [int(p['id']) for p in processes
                    if p['type'] == 'renderer' and owned_renderer(int(p['id']))]
                assert renderer_pids, 'no owned renderer processes found'
                for renderer_pid in renderer_pids:
                    os.kill(renderer_pid, signal.SIGKILL)
                result['intentionallyTerminatedRendererCount'] = len(renderer_pids)
                def crash_logged():
                    with sqlite3.connect(data / 'sirb.sqlite') as db:
                        return db.execute("SELECT COUNT(*) FROM error_logs WHERE type='crash'").fetchone()[0] > 0
                wait(crash_logged, 'native renderer termination was not recorded')
                time.sleep(.7)
                screenshot('after-intentional-crash')
                # Toolbar refresh remains available when the dead page no longer
                # owns keyboard focus. Keyboard Retry has widget coverage too.
                native.click_client(408, 28)
                time.sleep(1)
                screenshot('after-retry-click')
                (out / 'targets-after-retry.json').write_text(json.dumps(targets(), indent=2))
                replacement = wait(lambda: next((t for t in targets() if t['url'] == background_url and t['id'] != awake['id']), None),
                    'reload did not recreate crashed renderer')
                page = connect(replacement)
                time.sleep(1)
                screenshot('after-crash-retry', blue=True)
                result['checks']['explicit_renderer_crash_retry'] = True
                assert process.poll() is None, 'Sirb itself exited unexpectedly'
                result['appAliveBeforeIntentionalTestShutdown'] = True
                (out / 'lifecycle.json').write_text(json.dumps(result, indent=2))
                print(json.dumps(result, indent=2), flush=True)
            finally:
                for client in clients:
                    try:
                        client.close()
                    except Exception:
                        pass
                if native:
                    native.x.XCloseDisplay(native.d)
                # Clean up our child group even if its browser parent aborted.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
    server.shutdown()


if __name__ == '__main__':
    main()
