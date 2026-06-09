import AppKit

@MainActor
final class SelectionMonitor {
    private var eventMonitor: Any?
    private var mouseDownLocation: NSPoint?
    private var didDrag = false
    private var lastTriggerDate = Date.distantPast
    private let onSelectionGesture: () -> Void

    init(onSelectionGesture: @escaping () -> Void) {
        self.onSelectionGesture = onSelectionGesture
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = event.locationInWindow
            didDrag = false
        case .leftMouseDragged:
            guard let mouseDownLocation else { return }
            if distance(from: mouseDownLocation, to: event.locationInWindow) >= 8 {
                didDrag = true
            }
        case .leftMouseUp:
            guard didDrag else {
                mouseDownLocation = nil
                return
            }

            mouseDownLocation = nil
            didDrag = false

            guard Date().timeIntervalSince(lastTriggerDate) >= 0.8 else { return }
            lastTriggerDate = Date()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                onSelectionGesture()
            }
        default:
            break
        }
    }

    private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}
