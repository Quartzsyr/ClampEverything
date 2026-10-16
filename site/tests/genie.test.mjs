import test from 'node:test';
import assert from 'node:assert/strict';
import {genieRow} from '../assets/genie-motion.js';
test('genie preserves the real window at rest and feeds every row into its Dock icon',()=>{
 const source={x:520,y:90,width:620,height:590},dock={x:610,y:900,width:60,height:60};
 for(const row of [0,.2,.5,.8,1]){const original=genieRow(source,dock,0,row);assert.equal(original.left,source.x);assert.equal(original.right,source.x+source.width);assert.equal(original.y,source.y+source.height*row);const end=genieRow(source,dock,1,row);assert.ok(Math.abs(end.y-(dock.y+dock.height*.55))<1e-7);assert.ok(Math.abs(end.left-(dock.x+dock.width*.22))<1e-7);}
 const middle=genieRow(source,dock,.38,.5),bottom=genieRow(source,dock,.38,1),top=genieRow(source,dock,.38,0);assert.ok(bottom.right-bottom.left<top.right-top.left);assert.ok(middle.left>top.left&&middle.right<top.right,'curved taper rather than a uniformly scaled rectangle');
});
test('mesh rows remain ordered and within finite bounds throughout narrow and off-centre animations',()=>{
 for(const source of [{x:-50,y:50,width:420,height:600},{x:12,y:60,width:296,height:345}])for(const dock of [{x:0,y:450,width:32,height:49},{x:900,y:920,width:62,height:61}])for(let p=0;p<=1;p+=.025){let previous=-Infinity;for(let row=0;row<=1;row+=.025){const point=genieRow(source,dock,p,row);assert.ok(Number.isFinite(point.left+point.right+point.y));assert.ok(point.left<point.right);assert.ok(point.y>=previous-1e-6);previous=point.y;}}
});
