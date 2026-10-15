// dart run tool/export_video_policy.dart > /tmp/sirb-video-policy.json
// node tool/test_stream_compatibility.cjs /tmp/sirb-video-policy.json
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const script = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).streamCompatibility;
for (const host of ['www.twitch.tv', 'player.twitch.tv', 'kick.com', 'www.kick.com', 'notkick.com', 'twitch.tv.invalid', 'www.youtube.com']) {
  for (const frame of [false, true]) for (const supported of [[true,true], [true,false], [false,true], [false,false]]) {
    const reports = [], queries = [];
    const isTypeSupported = type => {
      queries.push(type); return type.includes('avc1') ? supported[0] : supported[1];
    };
    const scope = {location: {hostname: host, href: `https://${host}/fixture`},
      MediaSource: {isTypeSupported}, console: {debug: message => reports.push(JSON.parse(message.slice(8)))}};
    scope.window = scope; scope.top = frame ? {} : scope;
    vm.runInNewContext(script, scope);
    assert.equal(scope.MediaSource.isTypeSupported, isTypeSupported, 'Never spoof codec support');
    if (!frame && /(^|\.)(twitch\.tv|kick\.com)$/.test(host)) {
      assert.equal(reports.length, 1);
      assert.equal(reports[0].type, 'streamCompatibility');
      assert.equal(reports[0].h264, supported[0]);
      assert.equal(reports[0].aac, supported[1]);
      assert.equal(reports[0].main, true);
      assert.equal(queries.length, 2);
    } else {
      assert.equal(reports.length, 0); assert.equal(queries.length, 0);
    }
  }
}
console.log('Stream codec reporting passed: scoped, truthful, no API overrides or playback changes');
