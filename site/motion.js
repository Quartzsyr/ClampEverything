// Ported from PaperMotion.swift, CursorPickupMotion.swift and PhysicalMaterial.swift.
// Keep physical timing and hinge anchors shared with the native application.
export const HINGE = Object.freeze({ angle: 105, duration: 520, settle: 800, close: 280 });
export const MATERIALS = Object.freeze({
  note: { flexibility: 1, inertia: .32 }, photo: { flexibility: .55, inertia: .4 },
  folder: { flexibility: .18, inertia: .68 }, group: { flexibility: .12, inertia: .78 },
  document: { flexibility: .38, inertia: .6 }, word: { flexibility: .38, inertia: .6 },
  web: { flexibility: .65, inertia: .46 }, code: { flexibility: .05, inertia: .6 },
  audio: { flexibility: .05, inertia: .6 }, video: { flexibility: .45, inertia: .6 },
  archive: { flexibility: .22, inertia: .6 }, file: { flexibility: .05, inertia: .6 }
});
export const clamp = (x, min = 0, max = 1) => Math.min(max, Math.max(min, x));
export const ease = p => { p = clamp(p); return p * p * (3 - 2 * p); };
export function hingeAngle(progress, side = 'left') { return (1 - clamp(progress, 0, 1.025)) * HINGE.angle * (side === 'left' ? 1 : -1); }
export function pickupSample(progress, source, jaw, kind = 'note') {
  const p = clamp(progress), material = MATERIALS[kind] || MATERIALS.file;
  const travel = ease((p - .28) / .58), lp = ease((p - .1) / .76);
  const lift = lp > 0 && lp < 1 ? Math.sin(Math.PI * lp) : 0;
  const flutter = Math.sin(Math.PI * travel), pressure = Math.sin(Math.PI * Math.min(1, p / .28)) * (1 - travel);
  const settle = (p - .78) / .22;
  const recoil = settle > 0 && settle < 1 ? -Math.sin(settle * Math.PI * 2) * Math.exp(-settle * 3) * (1 + material.inertia * 2) : 0;
  const mix = (a, b) => a + (b - a) * travel;
  return { x: mix(source.x, jaw.x - 12), y: mix(source.y, jaw.y + 2) - lift * (8 + 7 * material.flexibility),
    width: mix(source.width, 22), height: mix(source.height, 28),
    compression: pressure * (.025 + material.flexibility * .045),
    angle: -6 * travel + flutter * material.flexibility * 7 + recoil,
    bend: flutter * material.flexibility * 12, shadow: 2 + lift * (3 + material.inertia * 3),
    jaw: 1 - ease((p - .48) / .4) };
}
export function placement(point, viewport, size) {
  const edge = point.x < 42 ? 'left' : point.x > viewport.width - 42 ? 'right' : null;
  const x = edge === 'left' ? 14 : edge === 'right' ? viewport.width - size.width - 14 : point.x - size.width * .65;
  return { edge, x: clamp(x, 8, Math.max(8, viewport.width - size.width - 8)),
    y: clamp(point.y - 26, 66, Math.max(66, viewport.height - size.height - 150)) };
}
