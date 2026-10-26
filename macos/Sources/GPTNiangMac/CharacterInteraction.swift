import SwiftUI
import AppKit

// AppKit handles pointer capture across a moving NSPanel. SwiftUI owns animation.
struct CharacterInteraction: NSViewRepresentable {
    var onPress: (Bool) -> Void
    var onDrag: (CGSize) -> Void
    var onClick: () -> Void
    var onMenu: (NSEvent, NSView) -> Void
    var locked = false
    var onRelease: (CGPoint) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var onPet: () -> Void = {}
    var onPointer: (CGPoint?) -> Void = { _ in }
    var tracksPlayPointer = false
    var pointerInterval = 1.0 / 30

    func makeNSView(context: Context) -> PointerView { let view = PointerView(); updateNSView(view, context: context); return view }
    func updateNSView(_ view: PointerView, context: Context) {
        view.onPress = onPress; view.onDrag = onDrag; view.onClick = onClick; view.onMenu = onMenu
        view.locked = locked; view.onRelease = onRelease
        view.onDoubleClick = onDoubleClick; view.onPet = onPet; view.onPointer = onPointer
        view.trackPointer(enabled: tracksPlayPointer, interval: pointerInterval)
    }
    static func dismantleNSView(_ view: PointerView, coordinator: ()) {
        view.cancelPendingGestures(); view.trackPointer(enabled: false, interval: 1)
    }
    final class PointerView: NSView {
        var onPress: (Bool) -> Void = { _ in }
        var onDrag: (CGSize) -> Void = { _ in }
        var onClick: () -> Void = {}
        var onMenu: (NSEvent, NSView) -> Void = { _, _ in }
        var locked = false
        var onRelease: (CGPoint) -> Void = { _ in }
        var onDoubleClick: () -> Void = {}
        var onPet: () -> Void = {}
        var onPointer: (CGPoint?) -> Void = { _ in }
        private var pendingClick: DispatchWorkItem?
        private var pendingPet: DispatchWorkItem?
        private var petTriggered = false
        private var pointerArea: NSTrackingArea?
        private var lastPointerTime: TimeInterval = 0
        private var pointerTimer: Timer?
        private var start: CGPoint?
        private var moved = false
        private var lastPoint: CGPoint?
        private var lastTime: TimeInterval = 0
        private var velocity = CGPoint.zero
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        func cancelPendingGestures() {
            pendingClick?.cancel(); pendingClick = nil
            pendingPet?.cancel(); pendingPet = nil
        }
        func trackPointer(enabled: Bool, interval: Double) {
            let cadence = max(1 / 30, interval)
            guard enabled else { pointerTimer?.invalidate(); pointerTimer = nil; return }
            if pointerTimer?.timeInterval == cadence { return }
            pointerTimer?.invalidate()
            // Nonactivating panels do not always receive mouseMoved events.
            // Poll only during the 12-second play state. A pointer beside the
            // character still supplies a direction; clamp the star to the canvas.
            let timer = Timer(timeInterval: cadence, repeats: true) { [weak self] _ in self?.pollPointer() }
            timer.tolerance = cadence * 0.15
            RunLoop.main.add(timer, forMode: .common); pointerTimer = timer
        }
        private func pollPointer() {
            guard let window else { return }
            let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            onPointer(CGPoint(x: min(0.94, max(0.06, local.x / max(1, bounds.width))),
                              y: min(0.94, max(0.06, local.y / max(1, bounds.height)))))
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerArea { removeTrackingArea(pointerArea) }
            let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area); pointerArea = area
        }
        private func normalizedPoint(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: min(1, max(0, p.x / max(1, bounds.width))), y: min(1, max(0, p.y / max(1, bounds.height))))
        }
        override func mouseMoved(with event: NSEvent) {
            guard event.timestamp - lastPointerTime >= 1 / 30 else { return }
            lastPointerTime = event.timestamp; onPointer(normalizedPoint(event))
        }
        override func mouseEntered(with event: NSEvent) { onPointer(normalizedPoint(event)) }
        override func mouseExited(with event: NSEvent) { if pointerTimer == nil { onPointer(nil) } }
        override func mouseDown(with event: NSEvent) {
            cancelPendingGestures(); petTriggered = false
            start = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            lastPoint = start; lastTime = event.timestamp; velocity = .zero
            moved = false; onPress(true)
            let p = normalizedPoint(event)
            if (0.30...0.70).contains(p.x) && p.y < 0.34 {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.start != nil, !self.moved else { return }
                    self.petTriggered = true; self.onPet()
                }
                pendingPet = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let now = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            let delta = CGSize(width: now.x - start.x, height: start.y - now.y)
            if moved || hypot(delta.width, delta.height) >= 3 {
                pendingPet?.cancel(); pendingPet = nil
                moved = true
                if !locked {
                    let dt = event.timestamp - lastTime
                    if let lastPoint, dt > 0.001, dt < 0.2 {
                        velocity = CGPoint(x: (now.x - lastPoint.x) / dt, y: (now.y - lastPoint.y) / dt)
                    }
                    lastPoint = now; lastTime = event.timestamp; onDrag(delta)
                }
            }
        }
        override func mouseUp(with event: NSEvent) {
            guard start != nil else { return }
            pendingPet?.cancel(); pendingPet = nil
            start = nil; onPress(false)
            if moved {
                if !locked {
                    onDrag(.zero)
                    onRelease(event.timestamp - lastTime < 0.12 ? velocity : .zero)
                }
            } else if !petTriggered {
                if event.clickCount >= 2 { pendingClick?.cancel(); pendingClick = nil; onDoubleClick() }
                else {
                    // Wait for the system double-click interval so a cuddle does
                    // not first flash the quota or request a quota refresh.
                    let work = DispatchWorkItem { [weak self] in self?.onClick() }
                    pendingClick = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval + 0.02, execute: work)
                }
            }
        }
        override func rightMouseDown(with event: NSEvent) { cancelPendingGestures(); onMenu(event, self) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
