// dart run tool/export_runtime_error_script.dart > /tmp/sirb-runtime-errors.js
// node tool/test_runtime_errors.cjs /tmp/sirb-runtime-errors.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const reports = [], nativeCalls = [];
const rejected = new Error('The root document of this element is not valid for pointer lock.');
class FakeElement extends EventTarget {
  requestPointerLock(...args) { nativeCalls.push({self:this,args}); return Promise.reject(rejected); }
  requestFullscreen() { return Promise.reject(new Error('Fullscreen denied')); }
}
class FakeMedia extends EventTarget { play() { return Promise.resolve(42); } }
class FakeAudio { resume() { return Promise.reject(new Error('Audio resume denied')); } }
class FakeAudioWorklet { addModule() { return Promise.reject(new Error('Worklet load failed')); } }
class FakeWorker extends EventTarget { constructor(url) { super(); this.url = url; } }
class FakeErrorEvent extends Event { constructor(message) { super('error'); this.message=message; this.filename='fixture.js'; this.lineno=7; } }
class FakeGPUAdapter { requestDevice() { return Promise.resolve(device); } }
let loseDevice;
const device = new EventTarget();
device.lost = new Promise(resolve => loseDevice=resolve);
const root = new EventTarget(), document = new EventTarget();
const scope = {
  console:{debug:text=>reports.push(JSON.parse(text.slice(8)))},
  location:{href:'https://fixture.test/game'}, document,
  addEventListener:root.addEventListener.bind(root),
  Element:FakeElement, HTMLMediaElement:FakeMedia,
  AudioContext:FakeAudio, webkitAudioContext:FakeAudio,
  AudioWorklet:FakeAudioWorklet, Worker:FakeWorker,
  GPUAdapter:FakeGPUAdapter, ErrorEvent:FakeErrorEvent,
};
scope.window=scope;scope.top=scope;
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'), scope);
(async()=>{
  const element=new FakeElement();
  await assert.rejects(element.requestPointerLock({unadjustedMovement:true}), error=>error===rejected);
  assert.equal(nativeCalls.length,1);
  assert.equal(nativeCalls[0].self,element);
  assert.deepEqual(nativeCalls[0].args,[{unadjustedMovement:true}]);
  assert.equal(await new FakeMedia().play(),42);
  await assert.rejects(new FakeAudio().resume(),/Audio resume denied/);
  assert.equal(reports.filter(r=>r.operation==='resume').length,1,'Audio aliases must not wrap twice');
  await assert.rejects(new FakeAudioWorklet().addModule(),/Worklet load failed/);
  root.dispatchEvent(new FakeErrorEvent('uncaught fixture'));
  const promiseEvent=new Event('unhandledrejection');promiseEvent.reason=new Error('Promise failed');root.dispatchEvent(promiseEvent);
  document.dispatchEvent(new Event('pointerlockerror'));
  document.dispatchEvent(new Event('webglcontextlost'));
  const worker=new scope.Worker('fixture-worker.js');
  assert.ok(worker instanceof FakeWorker);assert.equal(worker.url,'fixture-worker.js');
  worker.dispatchEvent(new FakeErrorEvent('worker fixture'));
  const adapter=new FakeGPUAdapter();
  assert.equal(await adapter.requestDevice(),device);
  loseDevice({reason:'unknown',message:'GPU lost fixture'});await Promise.resolve();
  assert.ok(reports.some(r=>r.operation==='GPUDevice.lost'&&r.category==='graphics'));
  assert.ok(reports.some(r=>r.operation==='Worker.error'&&r.category==='javascript'));
  assert.ok(reports.some(r=>r.operation==='unhandledrejection'));
  assert.ok(reports.some(r=>r.source==='fixture.js'&&r.line===7));
  assert.equal(Object.hasOwn(document,'pointerLockElement'),false,'Never spoof capture');
  assert.ok(reports.every(r=>r.url==='https://fixture.test/game'&&r.type==='runtimeError'));
  console.log(`Runtime error observers passed (${reports.length} reports; permissions/rejections preserved)`);
})().catch(error=>{console.error(error);process.exitCode=1;});
