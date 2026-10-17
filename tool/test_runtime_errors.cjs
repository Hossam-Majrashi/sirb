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
class FakeMedia extends EventTarget { play() { return this.failure ? Promise.reject(this.failure) : Promise.resolve(42); } }
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
  const media=new FakeMedia();
  for(const [name,message] of [
    ['AbortError','The play() request was interrupted by a call to pause(). https://goo.gl/LdLk22'],
    ['AbortError','The play() request was interrupted by a new load request.'],
    ['NotAllowedError','Sirb requires player interaction before playback'],
  ]){
    const before=reports.length;
    media.failure=Object.assign(new Error(message),{name});
    await assert.rejects(media.play(),e=>e===media.failure);
    const unhandled=new Event('unhandledrejection');unhandled.reason=media.failure;root.dispatchEvent(unhandled);
    assert.equal(reports.length,before,'Expected lifecycle/policy rejection is not a fault');
  }
  for(const name of ['NotSupportedError','NotAllowedError','AbortError']){
    const before=reports.length;
    media.failure=Object.assign(new Error('Real decoder/permission/operation failure'),{name});
    await assert.rejects(media.play(),e=>e===media.failure);
    const unhandled=new Event('unhandledrejection');unhandled.reason=media.failure;root.dispatchEvent(unhandled);
    assert.equal(reports.length,before+1,'Real errors stay visible without duplicate unhandled reports');
    assert.equal(reports.at(-1).category,'media');
  }
  const beforeResource=reports.length;
  const emptyResource=new Event('error');
  Object.defineProperty(emptyResource,'target',{value:{src:scope.location.href,getAttribute:()=>''}});
  root.dispatchEvent(emptyResource);
  assert.equal(reports.length,beforeResource,'Empty src must not falsely blame the document URL');
  const resource=new Event('error');
  Object.defineProperty(resource,'target',{value:{src:'https://fixture.test/missing.png',tagName:'IMG',getAttribute:key=>key==='src'?'/missing.png':null}});
  root.dispatchEvent(resource);
  assert.equal(reports.at(-1).source,'https://fixture.test/missing.png');
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
