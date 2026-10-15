import test from 'node:test';
import assert from 'node:assert/strict';
import {HoldGesture} from '../hold-gesture.js';
test('ordinary clicks cannot capture; Option remains held through mouse release',()=>{
 const g=new HoldGesture(); assert.equal(g.press(),false);g.hold();assert.equal(g.press(),true);assert.equal(g.release(),true);assert.equal(g.active,false);g.hold();assert.equal(g.active,false);g.unhold();g.hold();assert.equal(g.active,true);
});
test('early modifier release cancels; Escape/right-click suppress until release',()=>{
 const g=new HoldGesture();g.hold();g.press();g.unhold();assert.equal(g.release(),false);g.hold();g.cancel();assert.equal(g.press(),false);g.unhold();g.hold();assert.equal(g.press(),true);
});
