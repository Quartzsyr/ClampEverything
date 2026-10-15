// HoldShortcut.swift / PointClampController.receive: a completed or cancelled
// gesture cannot reactivate until the physical modifier has been released.
export class HoldGesture {
  held = false; cancelled = false; pressed = false;
  get active() { return this.held && !this.cancelled; }
  hold() { this.held = true; }
  press() { if (!this.active || this.pressed) return false; this.pressed = true; return true; }
  release() { if (!this.active || !this.pressed) return false; this.pressed = false; this.cancelled = true; return true; }
  cancel() { this.cancelled = this.held; this.pressed = false; }
  unhold() { this.held = false; this.cancelled = false; this.pressed = false; }
}
