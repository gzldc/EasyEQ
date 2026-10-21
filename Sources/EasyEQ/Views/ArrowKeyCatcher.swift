import AppKit
import SwiftUI

/// Invisible key responder that reports up/down arrow presses (used for sidebar keyboard navigation).
/// It takes first responder on appear and whenever `activation` changes (e.g. after a row click).
struct ArrowKeyCatcher: NSViewRepresentable {
    /// -1 for up, +1 for down.
    let onMove: (Int) -> Void
    let activation: Int

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onMove = onMove
        if view.lastActivation != activation {
            view.lastActivation = activation
            view.window?.makeFirstResponder(view)
        }
    }

    final class CatcherView: NSView {
        var onMove: ((Int) -> Void)?
        var lastActivation = 0

        override var acceptsFirstResponder: Bool { true }
        override var focusRingType: NSFocusRingType {
            get { .none }
            set {}
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onMove?(-1)   // up arrow
            case 125: onMove?(1)    // down arrow
            default: super.keyDown(with: event)
            }
        }
    }
}
