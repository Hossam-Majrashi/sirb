// dart run tool/export_media_policy.dart > /tmp/sirb-media-policy.json
// node tool/test_manual_playback.cjs /tmp/sirb-media-policy.json
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const policy=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
(async()=>{
  for(const speculative of [false,true]){
    let calls=0,pauses=0;
    const reports=[];
    class Element extends EventTarget {
      closest(selector){return selector==='video,audio'?this:null;}
      matches(){return false;}
    }
    class Media extends Element {
      play(...args){calls++;this.args=args;return Promise.resolve(42);}
      pause(){pauses++;}
    }
    const root=new EventTarget(),document=new EventTarget();
    const activation={hasBeenActive:false};
    const intents={};
    const add=document.addEventListener.bind(document);
    document.addEventListener=(name,listener,...args)=>{if(['pointerdown','click','keydown'].includes(name))intents[name]=listener;add(name,listener,...args);};
    const scope={HTMLMediaElement:Media,Element,ErrorEvent:class extends Event{},
      DOMException,navigator:{userActivation:activation},document,
      addEventListener:root.addEventListener.bind(root),
      console:{debug:line=>reports.push(JSON.parse(line.slice(8)))},
      location:{href:'https://fixture.test/watch'},__sirbSpeculative:speculative};
    scope.window=scope;scope.top=scope;
    vm.createContext(scope);
    vm.runInContext(policy.playback+policy.errors,scope);
    const media=new Media();
    await assert.rejects(media.play(),{name:'NotAllowedError'});
    assert.equal(calls,0,'Do not call native play then race it with pause');
    const event=new Event('play');Object.defineProperty(event,'target',{value:media});
    document.dispatchEvent(event);
    assert.equal(pauses,1,'Native HTML autoplay is stopped too');
    scope.__sirbSpeculative=false; // Foreground promotion is not media consent.
    await assert.rejects(media.play(),{name:'NotAllowedError'});
    assert.equal(calls,0);
    document.dispatchEvent(new Event('click'));
    await assert.rejects(media.play(),{name:'NotAllowedError'});
    activation.hasBeenActive=true;
    await assert.rejects(media.play(),{name:'NotAllowedError'},'Unrelated page activation is not media consent');
    intents.pointerdown({isTrusted:false,target:media,button:0});
    await assert.rejects(media.play(),{name:'NotAllowedError'},'Synthetic player events cannot grant consent');
    intents.pointerdown({isTrusted:true,target:media,button:2});
    await assert.rejects(media.play(),{name:'NotAllowedError'},'Opening the context menu is not play');
    intents.pointerdown({isTrusted:true,target:media,button:0});
    assert.equal(await media.play('fixture'),42);
    assert.deepEqual(media.args,['fixture']);
    assert.equal(calls,1);
    document.dispatchEvent(event);
    assert.equal(pauses,1,'Never pause user-started playback');
    const deepMedia=new Media();
    class Control extends Element {
      closest(selector){return selector==='button,[role="button"]'?this:null;}
      querySelectorAll(){return [];}
    }
    const control=new Control();let ancestor=control;
    for(let i=0;i<4;i++){const parent=new Control();ancestor.parentElement=parent;ancestor=parent;}
    ancestor.parentElement={querySelectorAll:()=>[deepMedia],parentElement:null};
    const icon=new Control();icon.closest=selector=>selector==='button,[role="button"]'?control:null;
    intents.pointerdown({isTrusted:false,target:icon,button:0});
    await assert.rejects(deepMedia.play(),{name:'NotAllowedError'});
    intents.pointerdown({isTrusted:true,target:icon,button:0});
    assert.equal(await deepMedia.play(),42,'Nested SVG player controls authorize their local media');
    vm.runInContext(policy.playback,scope);
    assert.equal(await media.play(),42,'Reinjection is idempotent');
    assert.equal(reports.length,0,'Policy denials are not runtime faults');
  }
  console.log('Manual playback policy passed (foreground/background, promotion, HTML autoplay, user activation, preserved results)');
})().catch(e=>{console.error(e);process.exitCode=1;});
