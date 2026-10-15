import test from 'node:test';
import assert from 'node:assert/strict';
import { HINGE, MATERIALS, hingeAngle, pickupSample, placement } from '../motion.js';

test('the complete assembly closes around its nail and opens to the same position', () => {
  assert.equal(hingeAngle(0), 105);
  assert.equal(hingeAngle(0, 'right'), -105);
  assert.equal(hingeAngle(1), 0);
  assert.ok(hingeAngle(1.02) < 0, 'a small spring overshoot is retained');
  assert.equal(HINGE.duration, 520);
});
test('every material starts at the source and hands off at one shared jaw', () => {
  const source = { x: 140, y: 180, width: 230, height: 170 }, jaw = { x: 550, y: 360 };
  for (const kind of Object.keys(MATERIALS)) {
    const first = pickupSample(0, source, jaw, kind), last = pickupSample(1, source, jaw, kind);
    assert.deepEqual([first.x, first.y, first.width, first.height], [140, 180, 230, 170]);
    assert.deepEqual([last.x, last.y, last.width, last.height], [538, 362, 22, 28]);
    assert.equal(last.compression, 0);
    for (let step = 0; step <= 100; step++) {
      const frame = pickupSample(step / 100, source, jaw, kind);
      assert.ok(Object.values(frame).every(Number.isFinite));
      assert.ok(frame.width >= 22 && frame.width <= 230);
      assert.ok(frame.height >= 28 && frame.height <= 170);
    }
  }
});
test('soft paper bends more than hard media without changing the pickup destination', () => {
  const source = { x: 0, y: 0, width: 200, height: 120 }, jaw = { x: 400, y: 300 };
  const paper = pickupSample(.5, source, jaw, 'note'), cassette = pickupSample(.5, source, jaw, 'audio');
  assert.ok(paper.bend > cassette.bend);
});
test('edge placement and small screens keep new objects reachable', () => {
  for (const viewport of [{ width: 390, height: 667 }, { width: 1440, height: 900 }]) {
    for (const point of [{ x: 2, y: 2 }, { x: viewport.width - 2, y: 900 }, { x: viewport.width / 2, y: 300 }]) {
      const r = placement(point, viewport, { width: 190, height: 280 });
      assert.ok(r.x >= 8 && r.x + 190 <= viewport.width - 8);
      assert.ok(r.y >= 66 && r.y + 280 <= viewport.height - 150);
    }
  }
});
