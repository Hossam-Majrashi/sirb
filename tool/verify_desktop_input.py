#!/usr/bin/env python3
"""Exercise real X11 input, Flutter accelerators and durable session changes."""
import argparse
import ctypes as C
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import time

p=argparse.ArgumentParser()
p.add_argument('--pid',type=int,required=True)
p.add_argument('--profile-data',required=True)
a=p.parse_args()
x=C.CDLL('libX11.so.6');xt=C.CDLL('libXtst.so.6')
x.XOpenDisplay.restype=C.c_void_p
x.XDefaultRootWindow.argtypes=[C.c_void_p];x.XDefaultRootWindow.restype=C.c_ulong
x.XStringToKeysym.argtypes=[C.c_char_p];x.XStringToKeysym.restype=C.c_ulong
x.XKeysymToKeycode.argtypes=[C.c_void_p,C.c_ulong];x.XKeysymToKeycode.restype=C.c_uint
x.XSetInputFocus.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_ulong]
x.XGetInputFocus.argtypes=[C.c_void_p,C.POINTER(C.c_ulong),C.POINTER(C.c_int)]
x.XRaiseWindow.argtypes=[C.c_void_p,C.c_ulong]
x.XFlush.argtypes=[C.c_void_p];x.XCloseDisplay.argtypes=[C.c_void_p]
xt.XTestFakeKeyEvent.argtypes=[C.c_void_p,C.c_uint,C.c_int,C.c_ulong]
d=x.XOpenDisplay(None)
if not d: raise RuntimeError('X11 display is required for native keyboard verification')
clients=subprocess.check_output(['xprop','-root','_NET_CLIENT_LIST'],text=True)
window=None
for candidate in re.findall(r'0x[0-9a-f]+',clients):
    data=subprocess.run(['xprop','-id',candidate,'_NET_WM_PID'],text=True,capture_output=True).stdout
    if re.search(r'=\s*'+str(a.pid)+r'\s*$',data):window=int(candidate,16);break
if not window:raise RuntimeError('No X11 window belongs to the requested process')
original=C.c_ulong();revert=C.c_int();x.XGetInputFocus(d,C.byref(original),C.byref(revert))
path=Path(a.profile_data)/'com.h.sirb/sirb.sqlite'
def snapshot():
    with sqlite3.connect(path) as c:
        row=c.execute('select snapshot,active from session where id=1').fetchone()
    return {'tabs':json.loads(row[0]),'active':row[1]}
def wait(predicate):
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        state=snapshot()
        if predicate(state):return state
        time.sleep(.05)
    raise AssertionError('Native shortcut did not produce its expected durable state')
def key(name,ctrl=False,shift=False):
    names=(['Control_L'] if ctrl else [])+(['Shift_L'] if shift else [])+[name]
    codes=[x.XKeysymToKeycode(d,x.XStringToKeysym(n.encode())) for n in names]
    for code in codes:xt.XTestFakeKeyEvent(d,code,1,0);x.XFlush(d);time.sleep(.025)
    for code in reversed(codes):xt.XTestFakeKeyEvent(d,code,0,0);x.XFlush(d);time.sleep(.025)
results={}
try:
    x.XRaiseWindow(d,window);x.XSetInputFocus(d,window,1,0);x.XFlush(d);time.sleep(.5)
    before=snapshot();n=len(before['tabs'])
    key('t',ctrl=True);wait(lambda s:len(s['tabs'])==n+1);results['ctrl_t']=True
    key('w',ctrl=True);wait(lambda s:len(s['tabs'])==n);results['ctrl_w']=True
    key('t',ctrl=True,shift=True);wait(lambda s:len(s['tabs'])==n+1);results['ctrl_shift_t']=True
    key('w',ctrl=True);wait(lambda s:len(s['tabs'])==n)
    active=snapshot()['active'];key('Tab',ctrl=True);wait(lambda s:s['active']!=active);results['ctrl_tab']=True
    key('1',ctrl=True);wait(lambda s:s['active']==s['tabs'][0]['id']);results['ctrl_1']=True
    key('9',ctrl=True);wait(lambda s:s['active']==s['tabs'][-1]['id']);results['ctrl_9']=True
    key('f',ctrl=True);time.sleep(.4)
    output=Path('build/runtime-evidence');output.mkdir(parents=True,exist_ok=True)
    subprocess.run(['import','-window',hex(window),str(output/'native-find.png')],check=True)
    key('F11');time.sleep(.4)
    fullscreen=subprocess.check_output(['xprop','-id',hex(window),'_NET_WM_STATE'],text=True)
    assert '_NET_WM_STATE_FULLSCREEN' in fullscreen
    key('F11');time.sleep(.3);results['f11']=True
    results['find_screenshot']=str(output/'native-find.png')
    results['session_tab_count']=n
    (output/'native-input.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results,indent=2))
finally:
    x.XSetInputFocus(d,original.value,revert.value,0);x.XFlush(d);x.XCloseDisplay(d)
