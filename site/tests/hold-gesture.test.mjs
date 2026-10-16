import test from 'node:test';
import assert from 'node:assert/strict';
import {HoldGesture} from '../hold-gesture.js';
test('capture begins only while armed; completion requires rearming',()=>{
 const g=new HoldGesture(); assert.equal(g.press(),false);g.hold();assert.equal(g.press(),true);assert.equal(g.release(),true);assert.equal(g.active,false);g.hold();assert.equal(g.active,false);g.unhold();g.hold();assert.equal(g.active,true);
});
test('cancelled input cannot complete; a new input can rearm',()=>{
 const g=new HoldGesture();g.hold();g.press();g.unhold();assert.equal(g.release(),false);g.hold();g.cancel();assert.equal(g.press(),false);g.unhold();g.hold();assert.equal(g.press(),true);
});
