#!/usr/bin/env python3
"""Linux X11 regression: real Sirb/CEF clipboard, focused iframe and Flutter fields.
Requires websocket-client and XTest. Launches only an isolated temporary profile,
with explicit loopback-only CDP. No signed media URLs or site permissions involved.
"""
import argparse
import ctypes as C
import http.server
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import threading
import time
import urllib.request

from verify_game import CDP


def wait(fn, description, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = fn()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError(description)


class XInput:
    def __init__(self, pid):
        self.x = C.CDLL('libX11.so.6')
        self.xt = C.CDLL('libXtst.so.6')
        x = self.x
        x.XOpenDisplay.restype = C.c_void_p
        x.XStringToKeysym.argtypes = [C.c_char_p]
        x.XStringToKeysym.restype = C.c_ulong
        x.XKeysymToKeycode.argtypes = [C.c_void_p, C.c_ulong]
        x.XKeysymToKeycode.restype = C.c_uint
        x.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
        x.XRaiseWindow.argtypes = [C.c_void_p, C.c_ulong]
        x.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong),
            C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint),
            C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
        x.XTranslateCoordinates.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong,
            C.c_int, C.c_int, C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_ulong)]
        x.XFlush.argtypes = [C.c_void_p]
        x.XCloseDisplay.argtypes = [C.c_void_p]
        self.xt.XTestFakeKeyEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
        self.xt.XTestFakeMotionEvent.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ulong]
        self.xt.XTestFakeButtonEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
        self.d = x.XOpenDisplay(None)
        if not self.d:
            raise RuntimeError('An X11 display is required')
        clients = subprocess.check_output(['xprop', '-root', '_NET_CLIENT_LIST'], text=True)
        self.window = None
        for candidate in re.findall(r'0x[0-9a-f]+', clients):
            prop = subprocess.check_output(['xprop', '-id', candidate, '_NET_WM_PID'], text=True)
            if re.search(r'=\s*' + str(pid) + r'\s*$', prop):
                self.window = int(candidate, 16)
                break
        if not self.window:
            raise RuntimeError('No X11 window for isolated Sirb')
        x.XRaiseWindow(self.d, self.window)
        x.XSetInputFocus(self.d, self.window, 1, 0)
        x.XFlush(self.d)
        time.sleep(.3)

    def key(self, name, ctrl=False):
        names = (['Control_L'] if ctrl else []) + [name]
        codes = [self.x.XKeysymToKeycode(self.d, self.x.XStringToKeysym(n.encode())) for n in names]
        for down, sequence in [(1, codes), (0, list(reversed(codes)))]:
            for code in sequence:
                self.xt.XTestFakeKeyEvent(self.d, code, down, 0)
                self.x.XFlush(self.d)
                time.sleep(.04)
        time.sleep(.2)

    def click_client(self, px, py):
        root, child = C.c_ulong(), C.c_ulong()
        gx, gy, rx, ry = C.c_int(), C.c_int(), C.c_int(), C.c_int()
        w, h, border, depth = C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
        self.x.XGetGeometry(self.d, self.window, C.byref(root), C.byref(gx), C.byref(gy),
            C.byref(w), C.byref(h), C.byref(border), C.byref(depth))
        self.x.XTranslateCoordinates(self.d, self.window, root.value, 0, 0,
            C.byref(rx), C.byref(ry), C.byref(child))
        self.xt.XTestFakeMotionEvent(self.d, -1, round(rx.value + px), round(ry.value + py), 0)
        for down in [1, 0]:
            self.xt.XTestFakeButtonEvent(self.d, 1, down, 0)
            self.x.XFlush(self.d)
            time.sleep(.08)
        time.sleep(.2)

    def click_element(self, page, selector, button=1):
        rect = page.evaluate('(()=>{const r=document.querySelector(' + json.dumps(selector) + ').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()')
        self.click_content(page, rect['x'], rect['y'], button=button)

    def click_content(self, page, px, py, button=1):
        root, child = C.c_ulong(), C.c_ulong()
        gx, gy, rx, ry = C.c_int(), C.c_int(), C.c_int(), C.c_int()
        w, h, border, depth = C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
        self.x.XGetGeometry(self.d, self.window, C.byref(root), C.byref(gx), C.byref(gy),
            C.byref(w), C.byref(h), C.byref(border), C.byref(depth))
        self.x.XTranslateCoordinates(self.d, self.window, root.value, 0, 0,
            C.byref(rx), C.byref(ry), C.byref(child))
        size = page.evaluate('({w:innerWidth,h:innerHeight,d:devicePixelRatio})')
        # Sirb content is bottom-right of its client area (rail at left, chrome above).
        self.xt.XTestFakeMotionEvent(self.d, -1,
            round(rx.value + w.value - size['w'] * size['d'] + px * size['d']),
            round(ry.value + h.value - size['h'] * size['d'] + py * size['d']), 0)
        for down in [1, 0]:
            self.xt.XTestFakeButtonEvent(self.d, button, down, 0)
            self.x.XFlush(self.d)
            time.sleep(.08)
        time.sleep(.2)


BODY = '''<!doctype html><meta charset="utf-8"><title>Clipboard fixture</title>
<style>input,textarea,[contenteditable]{display:block;width:400px;height:40px;margin:20px}
iframe{position:absolute;left:500px;top:20px;width:400px;height:150px}
#background{position:absolute;left:520px;top:220px}
#shadow{position:absolute;left:520px;top:260px}</style>
<input id="input" value="one عربي"><textarea id="area"></textarea>
<div id="rich" contenteditable></div><input id="url">
<a id="background" href="/background"><span>Open background</span></a>
<div id="shadow"></div>
<script>
window.counts={};window.frameState=null;
// A site window listener used to run before Sirb's document listener.
addEventListener('contextmenu',e=>{e.preventDefault();e.stopImmediatePropagation()});
const shadow=document.querySelector('#shadow').attachShadow({mode:'closed'});
shadow.innerHTML='<a href="/shadow-target" style="display:block;width:120px;height:25px">Shadow link</a>';
addEventListener('paste',e=>{const id=e.target.closest('[contenteditable]')?.id||e.target.id;counts[id]=(counts[id]||0)+1});
addEventListener('message',e=>{if(e.data?.fixture)frameState=e.data});
document.querySelector('#url').value=location.href+'?from=clipboard';
</script><iframe src="http://localhost:PORT/frame"></iframe>'''
FRAME = '''<!doctype html><meta charset="utf-8"><input id="frame" style="margin:20px;width:400px;height:50px">
<script>let pastes=0;addEventListener('paste',()=>pastes++);
addEventListener('input',()=>parent.postMessage({fixture:true,value:frame.value,pastes},'*'));</script>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', default='build/linux/x64/release/bundle/sirb')
    parser.add_argument('--port', type=int, default=9268)
    parser.add_argument('--output', default='build/clipboard-evidence')
    args = parser.parse_args()
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            text = FRAME if self.path == '/frame' else BODY.replace('PORT', str(self.server.server_port))
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(text.encode())
        def log_message(self, *args):
            pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/'
    with tempfile.TemporaryDirectory(prefix='sirb-clipboard-') as profile:
        data = Path(profile) / 'com.h.sirb'
        data.mkdir()
        (data / 'shared_preferences.json').write_text(json.dumps({
            'flutter.onboarding_done': True, 'flutter.startup': 'new',
            'flutter.gpu': 'auto', 'flutter.cpu': 0}))
        env = {**os.environ, 'XDG_DATA_HOME': profile, 'XDG_CONFIG_HOME': profile,
            'GDK_BACKEND': 'x11',
            'SIRB_CEF_SWITCHES': f'remote-debugging-port={args.port}'}
        with (out / 'sirb.log').open('w') as log:
            process = subprocess.Popen([str(Path(args.binary).resolve()), url], env=env,
                stdout=log, stderr=log, start_new_session=True)
            page = native = None
            try:
                def targets():
                    try:
                        return json.load(urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list'))
                    except OSError:
                        return []
                target = wait(lambda: next((t for t in targets() if t['url'] == url), None), 'fixture target')
                page = CDP(target['webSocketDebuggerUrl'])
                wait(lambda: page.evaluate('document.readyState') == 'complete', 'fixture ready')
                native = XInput(process.pid)
                result = {'engine': page.call('Browser.getVersion'), 'platform': 'Linux X11', 'checks': {}}
                # Copy from the actual web input, not a mocked system clipboard.
                native.click_element(page, '#input')
                native.key('a', ctrl=True)
                native.key('c', ctrl=True)
                native.key('BackSpace')
                native.key('v', ctrl=True)
                assert page.evaluate('input.value') == 'one عربي'
                assert page.evaluate('counts.input') == 1
                result['checks']['input_pastes_once'] = True
                native.key('z', ctrl=True)
                assert page.evaluate('input.value') == '', 'one undo removes the entire paste'
                native.key('y', ctrl=True)
                assert page.evaluate('input.value') == 'one عربي', 'one redo restores the paste'
                result['checks']['undo_redo_once'] = True
                for selector, expression in [('area', 'area.value'),
                        ('rich', 'rich.textContent')]:
                    native.click_element(page, '#' + selector)
                    native.key('v', ctrl=True)
                    assert page.evaluate(expression) == 'one عربي', selector
                    assert page.evaluate(f'counts.{selector}') == 1
                    result['checks'][selector + '_pastes_once'] = True
                # Real Flutter context menu on a nested contenteditable child:
                # CEF must preserve the focused frame/selection after menu focus.
                native.click_element(page, '#rich')
                native.key('a', ctrl=True)
                native.key('BackSpace')
                page.evaluate("rich.innerHTML='<span><b><br></b></span>'")
                rich = page.evaluate('(()=>{const r=rich.getBoundingClientRect();return {x:r.x+30,y:r.y+20}})()')
                native.click_content(page, rich['x'], rich['y'], button=3)
                native.click_content(page, rich['x']+40, rich['y']+30)
                wait(lambda: page.evaluate('rich.textContent') == 'one عربي', 'context-menu paste into contenteditable')
                assert page.evaluate('counts.rich') == 2, 'context paste must dispatch exactly once'
                result['checks']['context_menu_contenteditable_paste'] = True
                page.evaluate("rich.innerHTML='<span><b>comment copy عربي</b></span>'")
                native.click_content(page, rich['x'], rich['y'])
                native.key('a', ctrl=True)
                native.click_content(page, rich['x'], rich['y'], button=3)
                native.click_content(page, rich['x']+40, rich['y']+30)
                native.click_element(page, '#area')
                native.key('a', ctrl=True)
                native.key('v', ctrl=True)
                assert page.evaluate('area.value') == 'comment copy عربي', 'context-menu copy must reach the real clipboard'
                result['checks']['context_menu_rich_selection_copy'] = True
                # Restore fixture clipboard text for subsequent iframe checks.
                native.click_element(page, '#input')
                native.key('a', ctrl=True)
                native.key('c', ctrl=True)
                native.click_element(page, 'iframe')
                native.key('v', ctrl=True)
                wait(lambda: page.evaluate('frameState?.value') == 'one عربي', 'focused cross-origin frame paste')
                assert page.evaluate('frameState.pastes') == 1
                result['checks']['focused_cross_origin_frame'] = True
                native.key('a', ctrl=True)
                native.key('BackSpace')
                iframe = page.evaluate('(()=>{const r=document.querySelector("iframe").getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()')
                native.click_content(page, iframe['x'], iframe['y'], button=3)
                subprocess.run(['import', '-window', hex(native.window), str(out / 'iframe-menu.png')], check=True)
                # Menus on the right half of the window grow to the left.
                native.click_content(page, iframe['x']-40, iframe['y']+30)
                wait(lambda: page.evaluate('frameState?.value') == 'one عربي', 'iframe context-menu paste')
                assert page.evaluate('frameState.pastes') == 2
                result['checks']['iframe_context_menu_coordinates_and_paste'] = True
                for selector, path in [('#background', '/background'), ('#shadow', '/shadow-target')]:
                    rect = page.evaluate('(()=>{const r=document.querySelector('+json.dumps(selector)+').getBoundingClientRect();return {x:r.x+30,y:r.y+10}})()')
                    native.click_content(page, rect['x'], rect['y'], button=3)
                    native.click_content(page, rect['x']-40, rect['y']+30)
                    wait(lambda: any(t['url'] == url.rstrip('/')+path for t in targets()), 'background link from context menu '+path)
                    assert page.evaluate('location.href') == url
                result['checks']['window_handler_and_closed_shadow_links'] = True
                native.click_element(page, '#url')
                native.key('a', ctrl=True)
                native.key('c', ctrl=True)
                expected = url + '?from=clipboard'
                # Never submit an unknown clipboard to a public search engine.
                # Check the system selection before navigation, using GTK's own
                # clipboard API (same backend as this test's Flutter window).
                os.environ['GDK_BACKEND'] = 'x11'
                gtk = C.CDLL('libgtk-3.so.0')
                gdk = C.CDLL('libgdk-3.so.0')
                gtk.gtk_init_check(None, None)
                gdk.gdk_atom_intern.restype = C.c_void_p
                gdk.gdk_atom_intern.argtypes = [C.c_char_p, C.c_int]
                gtk.gtk_clipboard_get.restype = C.c_void_p
                gtk.gtk_clipboard_get.argtypes = [C.c_void_p]
                gtk.gtk_clipboard_wait_for_text.restype = C.c_char_p
                gtk.gtk_clipboard_wait_for_text.argtypes = [C.c_void_p]
                system_clipboard = gtk.gtk_clipboard_get(gdk.gdk_atom_intern(b'CLIPBOARD', 0))
                copied = gtk.gtk_clipboard_wait_for_text(system_clipboard)
                assert copied and copied.decode() == expected, 'CEF copy must reach OS clipboard'
                native.key('t', ctrl=True)
                # Explicitly focus the Flutter search field, as a user does.
                # This fixture uses the standard unscaled 1280x800 desktop.
                native.click_client(700, 336)
                native.key('v', ctrl=True)
                native.key('Return')
                target = wait(lambda: next((t for t in targets() if t['url'] == expected), None), 'new-tab Flutter paste/navigation')
                result['checks']['new_tab_search_paste'] = True
                page.close()
                page = CDP(target['webSocketDebuggerUrl'])
                wait(lambda: page.evaluate('document.readyState') == 'complete', 'new-tab navigation finished')
                page.evaluate('window.beforeAddressPaste=true')
                native.key('l', ctrl=True)
                native.key('a', ctrl=True)
                native.key('v', ctrl=True)
                native.key('Return')
                wait(lambda: page.evaluate('({url:location.href,reloaded:window.beforeAddressPaste===undefined})') ==
                    {'url': expected, 'reloaded': True}, 'address-bar paste/navigation')
                result['checks']['address_bar_paste'] = True
                (out / 'clipboard.json').write_text(json.dumps(result, indent=2))
                print(json.dumps(result, indent=2))
            except Exception:
                (out / 'failed-targets.json').write_text(json.dumps(targets(), indent=2))
                raise
            finally:
                if page:
                    page.close()
                if native:
                    native.x.XCloseDisplay(native.d)
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
    server.shutdown()


if __name__ == '__main__':
    main()
