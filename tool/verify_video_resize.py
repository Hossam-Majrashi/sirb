#!/usr/bin/env python3
"""Resize the actual Sirb window while YouTube plays; never emulate the viewport.
Requires websocket-client and Sirb with loopback CDP enabled. Linux uses X11
(run Sirb with GDK_BACKEND=x11 on Wayland); macOS needs Accessibility permission
for System Events; Windows uses user32. Native screenshots on Linux require import.
"""
import argparse
import ctypes as C
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.request

from verify_game import CDP


class NativeWindow:
    def __init__(self, pid):
        self.pid = pid
        if sys.platform.startswith('linux'):
            self.x = C.CDLL('libX11.so.6')
            self.x.XOpenDisplay.restype = C.c_void_p
            self.x.XResizeWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_uint, C.c_uint]
            self.x.XFlush.argtypes = [C.c_void_p]
            self.x.XCloseDisplay.argtypes = [C.c_void_p]
            self.display = self.x.XOpenDisplay(None)
            if not self.display:
                raise RuntimeError('X11/Xwayland required; start Sirb with GDK_BACKEND=x11')
            clients = subprocess.check_output(['xprop', '-root', '_NET_CLIENT_LIST'], text=True)
            self.window = None
            for candidate in re.findall(r'0x[0-9a-f]+', clients):
                data = subprocess.run(['xprop', '-id', candidate, '_NET_WM_PID'],
                                      text=True, capture_output=True).stdout
                if re.search(r'=\s*' + str(pid) + r'\s*$', data):
                    self.window = int(candidate, 16)
                    break
            if self.window is None:
                self.x.XCloseDisplay(self.display)
                raise RuntimeError('No X11 Sirb window belongs to this PID')
            self.x.XGetGeometry.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong),
                C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint),
                C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
            root, xpos, ypos = C.c_ulong(), C.c_int(), C.c_int()
            width, height, border, depth = (C.c_uint() for _ in range(4))
            if not self.x.XGetGeometry(self.display, self.window, C.byref(root),
                    C.byref(xpos), C.byref(ypos), C.byref(width), C.byref(height),
                    C.byref(border), C.byref(depth)):
                self.x.XCloseDisplay(self.display)
                raise RuntimeError('Cannot read Sirb window geometry')
            self.original = (width.value, height.value)
        elif sys.platform == 'win32':
            from ctypes import wintypes as W
            self.user32 = C.WinDLL('user32', use_last_error=True)
            callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
            self.user32.EnumWindows.argtypes = [callback_type, W.LPARAM]
            self.user32.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
            self.user32.IsWindowVisible.argtypes = [W.HWND]
            self.user32.GetWindowRect.argtypes = [W.HWND, C.POINTER(W.RECT)]
            self.user32.SetWindowPos.argtypes = [W.HWND, W.HWND, C.c_int, C.c_int,
                                               C.c_int, C.c_int, W.UINT]
            matches = []
            def visit(hwnd, _):
                owner = W.DWORD()
                self.user32.GetWindowThreadProcessId(hwnd, C.byref(owner))
                if owner.value == pid and self.user32.IsWindowVisible(hwnd):
                    matches.append(hwnd)
                return True
            self.user32.EnumWindows(callback_type(visit), 0)
            if not matches:
                raise RuntimeError('No visible Sirb window belongs to this PID')
            self.window = matches[0]
            rect = W.RECT()
            if not self.user32.GetWindowRect(self.window, C.byref(rect)):
                raise C.WinError(C.get_last_error())
            self.original = (rect.right - rect.left, rect.bottom - rect.top)
        elif sys.platform == 'darwin':
            size = self.apple('get size of front window')
            self.original = tuple(int(v.strip()) for v in size.split(','))
        else:
            raise RuntimeError('Desktop targets only')

    def apple(self, action):
        script = ('tell application "System Events"\n'
                  f'tell first application process whose unix id is {self.pid}\n'
                  f'{action}\nend tell\nend tell')
        return subprocess.check_output(['osascript', '-e', script], text=True).strip()

    def resize(self, width, height):
        if sys.platform.startswith('linux'):
            self.x.XResizeWindow(self.display, self.window, width, height)
            self.x.XFlush(self.display)
        elif sys.platform == 'win32':
            if not self.user32.SetWindowPos(self.window, None, 0, 0, width, height, 0x16):
                raise C.WinError(C.get_last_error())
        else:
            self.apple(f'set size of front window to {{{width}, {height}}}')

    def capture(self, path):
        if sys.platform.startswith('linux'):
            subprocess.run(['import', '-window', hex(self.window), str(path)], check=True)

    def close(self):
        self.resize(*self.original)
        if sys.platform.startswith('linux'):
            self.x.XCloseDisplay(self.display)


SAMPLE = """(()=>{const v=document.querySelector('video');if(!v)return null;
const rect=v.getBoundingClientRect(),q=v.getVideoPlaybackQuality();
return {viewport:[innerWidth,innerHeight],time:v.currentTime,paused:v.paused,
    ready:v.readyState,error:v.error?.code??null,decoded:q.totalVideoFrames,
    dropped:q.droppedVideoFrames,resolution:[v.videoWidth,v.videoHeight],
    rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},fit:getComputedStyle(v).objectFit};})()"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--port', type=int, default=9227)
    parser.add_argument('--url', default='https://www.youtube.com/watch?v=aqz-KE-bpKQ')
    parser.add_argument('--output', default='build/video-resize-evidence')
    parser.add_argument('--quality', choices=['hd2160', 'hd1440', 'hd1080', 'hd720', 'large', 'medium'])
    args = parser.parse_args()
    with urllib.request.urlopen(f'http://127.0.0.1:{args.port}/json/list', timeout=10) as response:
        pages = [t for t in json.load(response) if t['type'] == 'page']
    target = next((t for t in pages if t['url'] == args.url), pages[0])
    page = CDP(target['webSocketDebuggerUrl'])
    window = NativeWindow(args.pid)
    out = pathlib.Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    try:
        if target['url'] != args.url:
            page.call('Page.navigate', url=args.url)
        end = time.monotonic() + 60
        while time.monotonic() < end:
            sample = page.evaluate(SAMPLE)
            if sample and sample['ready'] >= 2:
                break
            time.sleep(1)
        else:
            raise RuntimeError('YouTube never reached a playable state')
        started = page.evaluate("document.querySelector('video').play().then(()=>true).catch(e=>e.message)", True)
        if started is not True:
            raise RuntimeError(f'Playback declined: {started}')
        if args.quality:
            page.evaluate('document.getElementById("movie_player")?.setPlaybackQualityRange?.('
                          + json.dumps(args.quality) + ')')
            time.sleep(8)
        time.sleep(3)
        result = {'platform': sys.platform, 'url': args.url, 'requestedQuality': args.quality,
                  'originalWindow': window.original,
                  'before': page.evaluate(SAMPLE), 'steps': []}
        window.capture(out / 'native-before.png')
        # Measure decode/playing and layout samples without modifying the player.
        page.evaluate("""(()=>{const samples=[];const timer=setInterval(()=>{
            const v=document.querySelector('video');if(v){const q=v.getVideoPlaybackQuality();
            samples.push({wall:performance.now(),time:v.currentTime,paused:v.paused,
                ready:v.readyState,viewport:[innerWidth,innerHeight],decoded:q.totalVideoFrames,dropped:q.droppedVideoFrames});}
            },100);window.__sirbResizeProbe={samples,timer};})()""")
        for index, size in enumerate([(800, 600), (1400, 900), (1000, 700), (1600, 900), (800, 600)]):
            window.resize(*size)
            time.sleep(.5)
            result['steps'].append({'requestedWindow': size, 'video': page.evaluate(SAMPLE)})
            window.capture(out / f'native-step-{index}.png')
        # A bidirectional live resize sweep, not just settled snapshots.
        for step in list(range(31)) + list(range(30, -1, -1)):
            window.resize(800 + step*20, 600 + step*10)
            time.sleep(.06)
            if step == 15:
                window.capture(out / f'native-during-{len(result["steps"])}.png')
                result['steps'].append({'requestedWindow': [1100, 750],
                                        'video': page.evaluate(SAMPLE)})
        time.sleep(2)
        result['samples'] = page.evaluate("""(()=>{const p=window.__sirbResizeProbe;
            clearInterval(p.timer);delete window.__sirbResizeProbe;return p.samples;})()""")
        result['after'] = page.evaluate(SAMPLE)
        window.capture(out / 'native-after.png')
        before, after = result['before'], result['after']
        result['summary'] = {
            'timeAdvanced': after['time'] - before['time'],
            'decodedFrames': after['decoded'] - before['decoded'],
            'droppedFrames': after['dropped'] - before['dropped'],
            'pausedSamples': sum(s['paused'] for s in result['samples']),
            'unreadySamples': sum(s['ready'] < 2 for s in result['samples']),
            'distinctViewports': len({tuple(s['viewport']) for s in result['samples']}),
            'note': 'Decode/layout samples do not prove compositor-presented FPS. Inspect native screenshots/recording for blank edges or scaling.'}
        (out / 'resize.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result['summary'], indent=2))
        assert after['time'] > before['time'] and after['decoded'] > before['decoded'], 'Video stopped'
        assert not after['paused'] and after['error'] is None, 'Playback failed'
        assert result['summary']['distinctViewports'] > 3, 'Actual window/CEF viewport did not resize'
        assert all(s['video']['fit'] == 'contain' for s in result['steps']), 'Video fit changed'
    finally:
        # Clean instrumentation even if native resizing/capture fails.
        try:
            page.evaluate('if(window.__sirbResizeProbe){clearInterval(__sirbResizeProbe.timer);delete window.__sirbResizeProbe;}')
        finally:
            window.close()
            page.close()


if __name__ == '__main__':
    main()
