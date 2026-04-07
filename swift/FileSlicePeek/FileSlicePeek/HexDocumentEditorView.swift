import AppKit
import SwiftUI

struct HexDocumentEditorView: View {
    @ObservedObject var model: HexDocumentModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Offset")
                    .frame(width: 104, alignment: .leading)

                Text("Hex")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Text")
                    .frame(width: 180, alignment: .leading)
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))

            Divider().overlay(Color.white.opacity(0.08))

            HexDocumentTextSurface(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(Color.black.opacity(0.12))
    }
}

private struct HexDocumentTextSurface: NSViewRepresentable {
    @ObservedObject var model: HexDocumentModel

    func makeCoordinator() -> HexDocumentEditorCoordinator {
        HexDocumentEditorCoordinator(model: model)
    }

    func makeNSView(context: Context) -> HexDocumentEditorSurface {
        let surface = HexDocumentEditorSurface()
        context.coordinator.attach(surface)
        context.coordinator.refresh(using: model)
        return surface
    }

    func updateNSView(_ nsView: HexDocumentEditorSurface, context: Context) {
        context.coordinator.attach(nsView)
        context.coordinator.refresh(using: model)
    }
}

private enum HexEditorPane {
    case offset
    case hex
    case text
}

private struct PendingHexNibble {
    let offset: Int
    let highNibble: UInt8
}

private struct HexEditorLayout {
    let dataCount: Int
    let rowCount: Int
    let addressWidth: Int
    let offsetString: String
    let hexString: String
    let textString: String
    let maxHexColumns: Int
    let maxTextColumns: Int

    init(data: Data) {
        dataCount = data.count
        rowCount = max(Int(ceil(Double(max(data.count, 1)) / Double(HexTools.bytesPerRow))), 1)
        addressWidth = max(8, String(max(data.count - 1, 0), radix: 16).count)

        var offsetLines = [String]()
        var hexLines = [String]()
        var textLines = [String]()

        offsetLines.reserveCapacity(rowCount)
        hexLines.reserveCapacity(rowCount)
        textLines.reserveCapacity(rowCount)

        for row in 0..<rowCount {
            let start = row * HexTools.bytesPerRow
            let end = min(start + HexTools.bytesPerRow, data.count)
            let rowBytes = start < end ? Array(data[start..<end]) : []

            offsetLines.append(HexTools.formatOffset(start, dataCount: max(data.count, 1)))
            hexLines.append(HexTools.hexList(from: rowBytes))
            textLines.append(rowBytes.map(HexTools.printableCharacter).joined())
        }

        offsetString = offsetLines.joined(separator: "\n")
        hexString = hexLines.joined(separator: "\n")
        textString = textLines.joined(separator: "\n")
        maxHexColumns = max(hexLines.map(\.count).max() ?? 0, HexTools.bytesPerRow * 3 - 1)
        maxTextColumns = max(textLines.map(\.count).max() ?? 0, HexTools.bytesPerRow)
    }

    func charRange(for byteRange: Range<Int>, in pane: HexEditorPane) -> NSRange {
        let clamped = clamp(byteRange)

        switch pane {
        case .offset:
            return NSRange(location: 0, length: 0)
        case .text:
            let start = textPosition(for: clamped.lowerBound)
            let end = textPosition(for: clamped.upperBound)
            return NSRange(location: start, length: max(end - start, 0))
        case .hex:
            let start = hexPosition(for: clamped.lowerBound)
            let length = hexLength(for: clamped)
            return NSRange(location: start, length: length)
        }
    }

    func byteRange(from selection: NSRange, in pane: HexEditorPane, minimumLength: Int = 1) -> Range<Int>? {
        guard dataCount > 0 else { return nil }

        let stringLength = switch pane {
        case .offset:
            0
        case .hex:
            hexString.utf16.count
        case .text:
            textString.utf16.count
        }

        let lowerBound = min(max(selection.location, 0), stringLength)
        let upperBound = min(max(selection.location + selection.length, 0), stringLength)

        let rawStart = switch pane {
        case .offset:
            0
        case .hex:
            hexStartBoundary(for: lowerBound)
        case .text:
            textStartBoundary(for: lowerBound)
        }

        let rawEnd = switch pane {
        case .offset:
            0
        case .hex:
            hexEndBoundary(for: upperBound)
        case .text:
            textEndBoundary(for: upperBound)
        }

        let start = min(max(rawStart, 0), max(dataCount - 1, 0))
        let minimumEnd = min(start + max(minimumLength, 1), dataCount)
        let end = min(max(rawEnd, minimumEnd), dataCount)
        return start..<max(end, minimumEnd)
    }

    private func clamp(_ byteRange: Range<Int>) -> Range<Int> {
        let lowerBound = min(max(byteRange.lowerBound, 0), dataCount)
        let upperBound = min(max(byteRange.upperBound, lowerBound), dataCount)
        return lowerBound..<upperBound
    }

    private func bytesInRow(_ row: Int) -> Int {
        let start = row * HexTools.bytesPerRow
        guard start < dataCount else { return 0 }
        return min(HexTools.bytesPerRow, dataCount - start)
    }

    private func textPosition(for byteBoundary: Int) -> Int {
        let clamped = min(max(byteBoundary, 0), dataCount)
        return (clamped / HexTools.bytesPerRow) * (HexTools.bytesPerRow + 1) + (clamped % HexTools.bytesPerRow)
    }

    private func hexPosition(for byteBoundary: Int) -> Int {
        let clamped = min(max(byteBoundary, 0), dataCount)
        return (clamped / HexTools.bytesPerRow) * (HexTools.bytesPerRow * 3) + (clamped % HexTools.bytesPerRow) * 3
    }

    private func hexLength(for byteRange: Range<Int>) -> Int {
        guard byteRange.isEmpty == false else { return 0 }

        var cursor = byteRange.lowerBound
        var remaining = byteRange.count
        var length = 0

        while remaining > 0 {
            let column = cursor % HexTools.bytesPerRow
            let bytesThisRow = min(HexTools.bytesPerRow - column, remaining)
            length += bytesThisRow * 3 - 1
            cursor += bytesThisRow
            remaining -= bytesThisRow

            if remaining > 0 {
                length += 1
            }
        }

        return length
    }

    private func textStartBoundary(for position: Int) -> Int {
        let row = position / (HexTools.bytesPerRow + 1)
        let column = position % (HexTools.bytesPerRow + 1)
        let rowStart = min(row * HexTools.bytesPerRow, dataCount)
        let bytes = min(HexTools.bytesPerRow, max(dataCount - rowStart, 0))

        if column >= bytes {
            return min(rowStart + bytes, dataCount)
        }

        return rowStart + column
    }

    private func textEndBoundary(for position: Int) -> Int {
        guard position > 0 else { return 0 }

        let previous = position - 1
        let row = previous / (HexTools.bytesPerRow + 1)
        let column = previous % (HexTools.bytesPerRow + 1)
        let rowStart = min(row * HexTools.bytesPerRow, dataCount)
        let bytes = min(HexTools.bytesPerRow, max(dataCount - rowStart, 0))

        if column >= bytes {
            return min(rowStart + bytes, dataCount)
        }

        return min(rowStart + column + 1, dataCount)
    }

    private func hexStartBoundary(for position: Int) -> Int {
        let rowStride = HexTools.bytesPerRow * 3
        let row = position / rowStride
        let column = position % rowStride
        let rowStart = min(row * HexTools.bytesPerRow, dataCount)
        let bytes = bytesInRow(row)
        let rowLength = max(bytes * 3 - 1, 0)

        guard bytes > 0 else { return rowStart }

        if column >= rowLength {
            return min(rowStart + bytes, dataCount)
        }

        let byteIndex = min(column / 3, bytes - 1)

        if column % 3 == 2 {
            return min(rowStart + byteIndex + 1, rowStart + bytes)
        }

        return min(rowStart + byteIndex, rowStart + bytes)
    }

    private func hexEndBoundary(for position: Int) -> Int {
        guard position > 0 else { return 0 }

        let rowStride = HexTools.bytesPerRow * 3
        let previous = position - 1
        let row = previous / rowStride
        let column = previous % rowStride
        let rowStart = min(row * HexTools.bytesPerRow, dataCount)
        let bytes = bytesInRow(row)
        let rowLength = max(bytes * 3 - 1, 0)

        guard bytes > 0 else { return rowStart }

        if column >= rowLength {
            return min(rowStart + bytes, dataCount)
        }

        let byteIndex = min(column / 3, bytes - 1)
        return min(rowStart + byteIndex + 1, rowStart + bytes)
    }
}

private final class HexDocumentEditorCoordinator: NSObject, NSTextViewDelegate {
    private weak var surface: HexDocumentEditorSurface?
    private weak var model: HexDocumentModel?
    private var layout = HexEditorLayout(data: Data())
    private weak var lastRenderedSurface: HexDocumentEditorSurface?
    private var lastAppliedContentToken = -1
    private var isApplyingViewUpdate = false
    private var isSynchronizingSelection = false
    private var suppressScrollOnNextRefresh = false
    private var pendingHexNibble: PendingHexNibble?

    init(model: HexDocumentModel) {
        self.model = model
    }

    func attach(_ surface: HexDocumentEditorSurface) {
        if self.surface !== surface {
            self.surface = surface
            surface.install(delegate: self)
        }
    }

    func refresh(using model: HexDocumentModel) {
        self.model = model
        let shouldScroll = suppressScrollOnNextRefresh == false
        suppressScrollOnNextRefresh = false
        let shouldApplyContent = lastAppliedContentToken != model.contentRefreshToken || surface !== lastRenderedSurface

        if shouldApplyContent {
            let nextLayout = HexEditorLayout(data: model.dataSnapshot)
            layout = nextLayout
            lastAppliedContentToken = model.contentRefreshToken
            lastRenderedSurface = surface

            if let pendingHexNibble, pendingHexNibble.offset >= nextLayout.dataCount {
                self.pendingHexNibble = nil
            }
        }

        isApplyingViewUpdate = true
        if shouldApplyContent {
            surface?.apply(layout: layout)
        }

        if let byteRange = selectedByteRange(for: model, dataCount: layout.dataCount) {
            surface?.applySelection(byteRange: byteRange, layout: layout, scrollToVisible: shouldScroll)

            if let pendingHexNibble, pendingHexNibble.offset != byteRange.lowerBound {
                self.pendingHexNibble = nil
            }
        } else {
            surface?.clearSelection()
            pendingHexNibble = nil
        }

        isApplyingViewUpdate = false
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard
            isApplyingViewUpdate == false,
            isSynchronizingSelection == false,
            let textView = notification.object as? HexPaneTextView,
            let model,
            textView.pane != .offset,
            let byteRange = layout.byteRange(from: textView.selectedRange(), in: textView.pane)
        else {
            return
        }

        pendingHexNibble = nil
        suppressScrollOnNextRefresh = true
        isSynchronizingSelection = true
        surface?.applySelection(byteRange: byteRange, layout: layout, scrollToVisible: false)
        isSynchronizingSelection = false

        if model.selectionStart != byteRange.lowerBound || model.selectionLength != byteRange.count {
            model.selectRange(start: byteRange.lowerBound, length: byteRange.count)
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard
            isApplyingViewUpdate == false,
            let paneView = textView as? HexPaneTextView,
            let replacementString,
            let model,
            paneView.pane != .offset,
            let byteRange = layout.byteRange(from: affectedCharRange, in: paneView.pane)
        else {
            return false
        }

        switch paneView.pane {
        case .offset:
            return false
        case .text:
            pendingHexNibble = nil
            suppressScrollOnNextRefresh = true
            _ = model.replaceTextInput(replacementString, at: byteRange.lowerBound, replacing: byteRange.count)
        case .hex:
            applyHexReplacement(replacementString, to: byteRange, model: model)
        }

        return false
    }

    private func applyHexReplacement(_ replacement: String, to byteRange: Range<Int>, model: HexDocumentModel) {
        let trimmedScalars = replacement.unicodeScalars.filter { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false
        }

        let hasInvalidCharacters = trimmedScalars.contains { scalar in
            CharacterSet(charactersIn: "0123456789ABCDEFabcdef").contains(scalar) == false
        }

        guard hasInvalidCharacters == false else {
            NSSound.beep()
            return
        }

        let hexDigits = replacement.uppercased().filter(\.isHexDigit)

        if replacement.isEmpty {
            pendingHexNibble = nil
            suppressScrollOnNextRefresh = true
            _ = model.replaceHexInput("", at: byteRange.lowerBound, replacing: byteRange.count)
            return
        }

        if hexDigits.count == 1, byteRange.count == 1, let digit = UInt8(hexDigits, radix: 16) {
            suppressScrollOnNextRefresh = true
            applySingleHexDigit(digit, at: byteRange.lowerBound, model: model)
            return
        }

        guard hexDigits.isEmpty == false else {
            return
        }

        pendingHexNibble = nil
        suppressScrollOnNextRefresh = true
        _ = model.replaceHexInput(replacement, at: byteRange.lowerBound, replacing: byteRange.count)
    }

    private func applySingleHexDigit(_ digit: UInt8, at offset: Int, model: HexDocumentModel) {
        guard let currentByte = model.byteValue(at: offset) else {
            NSSound.beep()
            pendingHexNibble = nil
            return
        }

        if let pendingHexNibble, pendingHexNibble.offset == offset {
            let completedByte = (pendingHexNibble.highNibble << 4) | digit
            self.pendingHexNibble = nil
            _ = model.replaceHexInput(HexTools.formatHexByte(completedByte), at: offset, replacing: 1)

            if model.dataCount > 0 {
                let nextOffset = min(offset + 1, model.dataCount - 1)
                model.selectRange(start: nextOffset, length: 1)
            }
        } else {
            let stagedByte = (digit << 4) | (currentByte & 0x0F)
            pendingHexNibble = PendingHexNibble(offset: offset, highNibble: digit)
            _ = model.replaceHexInput(HexTools.formatHexByte(stagedByte), at: offset, replacing: 1)
            model.selectRange(start: offset, length: 1)
        }
    }

    private func selectedByteRange(for model: HexDocumentModel, dataCount: Int) -> Range<Int>? {
        guard dataCount > 0, let selectionStart = model.selectionStart else {
            return nil
        }

        let start = min(max(selectionStart, 0), dataCount - 1)
        let length = min(max(model.selectionLength, 1), dataCount - start)
        return start..<(start + length)
    }
}

private final class HexDocumentEditorSurface: FlippedView {
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let offsetBackground = NSView()
    private let hexBackground = NSView()
    private let textBackground = NSView()
    private let dividerOne = NSView()
    private let dividerTwo = NSView()
    private let offsetTextView = HexPaneTextView(pane: .offset, editable: false)
    private let hexTextView = HexPaneTextView(pane: .hex, editable: true)
    private let textTextView = HexPaneTextView(pane: .text, editable: true)

    private let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    private let paragraphStyle: NSParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = 2
        return paragraphStyle
    }()

    private var currentLayout = HexEditorLayout(data: Data())

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        relayoutColumns(using: currentLayout)
    }

    func install(delegate: NSTextViewDelegate) {
        hexTextView.delegate = delegate
        textTextView.delegate = delegate
    }

    func apply(layout: HexEditorLayout) {
        currentLayout = layout
        setContent(layout.offsetString, for: offsetTextView, color: NSColor.white.withAlphaComponent(0.72))
        setContent(layout.hexString, for: hexTextView, color: NSColor(calibratedWhite: 0.92, alpha: 1))
        setContent(layout.textString, for: textTextView, color: NSColor(calibratedWhite: 0.98, alpha: 1))
        relayoutColumns(using: layout)
    }

    func applySelection(byteRange: Range<Int>, layout: HexEditorLayout, scrollToVisible: Bool) {
        let hexRange = layout.charRange(for: byteRange, in: .hex)
        let textRange = layout.charRange(for: byteRange, in: .text)

        if hexTextView.selectedRange() != hexRange {
            hexTextView.setSelectedRange(hexRange)
        }

        if textTextView.selectedRange() != textRange {
            textTextView.setSelectedRange(textRange)
        }

        if scrollToVisible {
            scrollSelectionIntoView(hexRange, in: hexTextView)
        }
    }

    func clearSelection() {
        hexTextView.setSelectedRange(NSRange(location: 0, length: 0))
        textTextView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    private func configureSurface() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        addSubview(scrollView)

        configureBackground(offsetBackground, color: NSColor(calibratedWhite: 1, alpha: 0.035))
        configureBackground(hexBackground, color: NSColor(calibratedWhite: 0, alpha: 0.18))
        configureBackground(textBackground, color: NSColor(calibratedWhite: 1, alpha: 0.065))
        configureBackground(dividerOne, color: NSColor.white.withAlphaComponent(0.12))
        configureBackground(dividerTwo, color: NSColor.white.withAlphaComponent(0.12))

        [offsetBackground, hexBackground, textBackground, dividerOne, dividerTwo].forEach(documentView.addSubview)
        [offsetTextView, hexTextView, textTextView].forEach(documentView.addSubview)
    }

    private func configureBackground(_ view: NSView, color: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
    }

    private func setContent(_ string: String, for textView: HexPaneTextView, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: editorFont,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        textView.textStorage?.setAttributedString(NSAttributedString(string: string, attributes: attributes))
        textView.typingAttributes = attributes
    }

    private func relayoutColumns(using layout: HexEditorLayout) {
        let characterWidth = ("0" as NSString).size(withAttributes: [.font: editorFont]).width
        let gap: CGFloat = 12
        let offsetWidth = ceil(characterWidth * CGFloat(layout.addressWidth) + 20)
        let hexWidth = ceil(characterWidth * CGFloat(layout.maxHexColumns) + 20)
        let textWidth = ceil(characterWidth * CGFloat(layout.maxTextColumns) + 20)

        let contentHeight = max(
            measuredHeight(for: offsetTextView),
            measuredHeight(for: hexTextView),
            measuredHeight(for: textTextView),
            bounds.height
        )

        let totalWidth = offsetWidth + gap + hexWidth + gap + textWidth

        documentView.frame = NSRect(x: 0, y: 0, width: totalWidth, height: contentHeight)

        position(textView: offsetTextView, x: 0, width: offsetWidth, height: contentHeight)
        position(textView: hexTextView, x: offsetWidth + gap, width: hexWidth, height: contentHeight)
        position(textView: textTextView, x: offsetWidth + gap + hexWidth + gap, width: textWidth, height: contentHeight)

        offsetBackground.frame = offsetTextView.frame
        hexBackground.frame = hexTextView.frame
        textBackground.frame = textTextView.frame
        dividerOne.frame = NSRect(x: offsetWidth + gap / 2, y: 0, width: 1, height: contentHeight)
        dividerTwo.frame = NSRect(x: offsetWidth + gap + hexWidth + gap / 2, y: 0, width: 1, height: contentHeight)
    }

    private func position(textView: NSTextView, x: CGFloat, width: CGFloat, height: CGFloat) {
        textView.frame = NSRect(x: x, y: 0, width: width, height: height)
        textView.minSize = NSSize(width: width, height: height)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: width - textView.textContainerInset.width * 2, height: CGFloat.greatestFiniteMagnitude)
    }

    private func measuredHeight(for textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return bounds.height
        }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.height + textView.textContainerInset.height * 2 + 2)
    }

    private func scrollSelectionIntoView(_ range: NSRange, in textView: NSTextView) {
        guard
            range.length > 0,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: textView.string.utf16.count))
        guard safeRange.length > 0 else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: safeRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.frame.minX + textView.textContainerInset.width
        rect.origin.y += textView.frame.minY + textView.textContainerInset.height
        rect = rect.insetBy(dx: -12, dy: -18)
        documentView.scrollToVisible(rect)
    }
}

private final class HexPaneTextView: NSTextView {
    let pane: HexEditorPane

    init(pane: HexEditorPane, editable: Bool) {
        self.pane = pane

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        super.init(frame: .zero, textContainer: textContainer)

        isEditable = editable
        isSelectable = pane != .offset
        drawsBackground = false
        backgroundColor = .clear
        isRichText = false
        importsGraphics = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        allowsUndo = false
        usesAdaptiveColorMappingForDarkAppearance = true
        insertionPointColor = NSColor.white
        textContainerInset = NSSize(width: 10, height: 10)
        font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        textColor = NSColor(calibratedWhite: 0.98, alpha: 1)
        selectedTextAttributes = [
            .backgroundColor: NSColor(calibratedRed: 0.41, green: 0.58, blue: 0.94, alpha: 0.95),
            .foregroundColor: NSColor.black
        ]

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        usesFindBar = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}
