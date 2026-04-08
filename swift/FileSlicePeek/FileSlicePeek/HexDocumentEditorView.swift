import AppKit
import SwiftUI

struct HexDocumentEditorView: NSViewRepresentable {
    @ObservedObject var model: HexDocumentModel

    func makeNSView(context: Context) -> EditorHostView {
        let host = EditorHostView()
        host.embed(model.editorView)
        return host
    }

    func updateNSView(_ nsView: EditorHostView, context: Context) {
        nsView.embed(model.editorView)
    }
}

final class EditorHostView: NSView {
    private weak var embeddedView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func embed(_ view: NSView) {
        guard embeddedView !== view else {
            updateBackground()
            return
        }

        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        embeddedView = view
        updateBackground()
    }

    override func layout() {
        super.layout()
        embeddedView?.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
            : NSColor(calibratedRed: 0.98, green: 0.99, blue: 1, alpha: 1)
        ).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (isDark ? NSColor.separatorColor : NSColor.gridColor.withAlphaComponent(0.35)).cgColor
    }
}
