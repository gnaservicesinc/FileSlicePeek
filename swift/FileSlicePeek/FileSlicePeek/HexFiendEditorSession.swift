import AppKit
import Foundation
import HexFiend

@MainActor
final class HexFiendEditorSession: NSObject {
    struct SelectionState {
        let start: Int?
        let length: Int
        let previewData: Data
        let previewIsTruncated: Bool
        let totalLength: Int
    }

    struct DocumentState {
        let byteCount: Int
        let isDirty: Bool
        let isEditable: Bool
    }

    enum SearchDirection {
        case forward
        case backward
    }

    var onSelectionChange: ((SelectionState) -> Void)?
    var onDocumentChange: ((DocumentState) -> Void)?

    private let controller = HFController()
    private let layoutRepresenter = HFLayoutRepresenter()
    private let lineCountingRepresenter = HFLineCountingRepresenter()
    private let hexRepresenter = HFHexTextRepresenter()
    private let textRepresenter = HFStringEncodingTextRepresenter()
    private let scrollerRepresenter = HFVerticalScrollerRepresenter()
    private let statusRepresenter = HFStatusBarRepresenter()
    private let rootView = NSView(frame: .zero)
    private let previewByteLimit = 256

    private var sourceURL: URL?
    private var writableReference: HFFileReference?
    private var readOnlyReference: HFFileReference?
    private var generationAtLoad: UInt = 0
    private var isApplyingSelection = false
    private var controllerObserver: NSObjectProtocol?

    override init() {
        super.init()
        configureRepresenters()
        configureController()
        configureRootView()
        installNotificationObserver()
        applySelectionChange()
        applyDocumentChange()
    }

    deinit {
        if let controllerObserver {
            NotificationCenter.default.removeObserver(controllerObserver)
        }
    }

    var mountedView: NSView {
        rootView
    }

    var byteCount: Int {
        Int(clamping: controller.contentsLength())
    }

    var isDirty: Bool {
        controller.byteArray.changeGenerationCount() != generationAtLoad
    }

    var hasDocument: Bool {
        sourceURL != nil
    }

    func loadDocument(at url: URL) throws {
        let writableReference = try? HFFileReference(writableWithPath: url.path)
        let fileReference = try writableReference ?? HFFileReference(path: url.path)

        let fileSlice = HFFileByteSlice(file: fileReference)
        let byteArray = HFBTreeByteArray()
        byteArray.insertByteSlice(fileSlice, in: HFRangeMake(0, 0))

        sourceURL = url
        self.writableReference = writableReference
        readOnlyReference = fileReference

        controller.byteArray = byteArray
        controller.editable = writableReference != nil
        controller.savable = writableReference != nil
        controller.editMode = HFEditMode(rawValue: 1)!
        generationAtLoad = byteArray.changeGenerationCount()

        let initialLength = min(1, byteCount)
        controller.selectedContentsRanges = [HFRangeWrapper.withRange(HFRangeMake(0, UInt64(initialLength)))]
        applySelectionChange()
        applyDocumentChange()
    }

    func saveDocument() throws {
        guard let sourceURL else { return }
        try controller.byteArray.write(toFile: sourceURL, trackingProgress: nil)
        generationAtLoad = controller.byteArray.changeGenerationCount()
        applyDocumentChange()
    }

    func revertDocument() throws {
        guard let sourceURL else { return }
        try loadDocument(at: sourceURL)
    }

    func selectRange(start: Int, length: Int) {
        guard byteCount > 0 else { return }
        let clampedStart = min(max(start, 0), max(byteCount - 1, 0))
        let clampedLength = min(max(length, 0), byteCount - clampedStart)
        applySelection(HFRangeMake(UInt64(clampedStart), UInt64(clampedLength)))
    }

    func replaceSelection(with replacement: Data) {
        guard hasDocument else { return }
        let replacementArray = HexTools.byteArray(from: replacement)
        _ = controller.insertByteArray(replacementArray, replacingPreviousBytes: 0, allowUndoCoalescing: false)
    }

    func replaceAll(pattern: Data, replacement: Data) -> Int {
        guard pattern.isEmpty == false, hasDocument else { return 0 }

        let needle = HexTools.byteArray(from: pattern)
        let replacementArray = HexTools.byteArray(from: replacement)
        let patternLength = UInt64(pattern.count)
        let replacementLength = UInt64(replacement.count)

        var replacements = 0
        var searchLocation: UInt64 = 0
        let transaction = controller.beginPropertyChangeTransaction()

        defer {
            controller.endPropertyChangeTransaction(transaction)
            applySelectionChange()
            applyDocumentChange()
        }

        while searchLocation <= controller.contentsLength() {
            let contentsLength = controller.contentsLength()
            guard contentsLength >= patternLength else { break }
            guard searchLocation <= contentsLength - patternLength else { break }

            let searchRange = HFRangeMake(searchLocation, contentsLength - searchLocation)
            let matchLocation = controller.byteArray.indexOfBytesEqual(to: needle, in: searchRange, searchingForwards: true, trackingProgress: nil)

            guard matchLocation != UInt64.max else { break }

            applySelection(HFRangeMake(matchLocation, patternLength))
            _ = controller.insertByteArray(replacementArray, replacingPreviousBytes: 0, allowUndoCoalescing: false)

            replacements += 1
            searchLocation = matchLocation + replacementLength
        }

        if replacements > 0 {
            controller.pulseSelection()
        }

        return replacements
    }

    @discardableResult
    func find(pattern: Data, direction: SearchDirection) -> Bool {
        guard pattern.isEmpty == false, hasDocument else { return false }

        let needle = HexTools.byteArray(from: pattern)
        let currentSelection = currentSelectionRange()
        let totalLength = controller.contentsLength()

        let foundLocation: UInt64
        switch direction {
        case .forward:
            let start = min(currentSelection.location + currentSelection.length, totalLength)
            let forwardLength = totalLength - start
            let forwardResult = controller.byteArray.indexOfBytesEqual(to: needle, in: HFRangeMake(start, forwardLength), searchingForwards: true, trackingProgress: nil)
            if forwardResult != UInt64.max {
                foundLocation = forwardResult
            } else {
                foundLocation = controller.byteArray.indexOfBytesEqual(to: needle, in: HFRangeMake(0, start), searchingForwards: true, trackingProgress: nil)
            }

        case .backward:
            let end = min(currentSelection.location, totalLength)
            let backwardResult = controller.byteArray.indexOfBytesEqual(to: needle, in: HFRangeMake(0, end), searchingForwards: false, trackingProgress: nil)
            if backwardResult != UInt64.max {
                foundLocation = backwardResult
            } else {
                foundLocation = controller.byteArray.indexOfBytesEqual(to: needle, in: HFRangeMake(end, totalLength - end), searchingForwards: false, trackingProgress: nil)
            }
        }

        guard foundLocation != UInt64.max else { return false }
        applySelection(HFRangeMake(foundLocation, UInt64(pattern.count)))
        controller.pulseSelection()
        return true
    }

    func selectionStartsWith(_ pattern: Data) -> Bool {
        guard pattern.isEmpty == false else { return false }
        let selection = currentSelectionRange()
        guard selection.length == UInt64(pattern.count) else { return false }
        let preview = data(in: selection)
        return preview == pattern
    }

    func selectedPreview() -> (hex: String, text: String) {
        let selection = currentSelectionRange()
        guard selection.length > 0 else { return ("", "") }
        let previewLength = min(Int(selection.length), previewByteLimit)
        let previewRange = HFRangeMake(selection.location, UInt64(previewLength))
        let data = data(in: previewRange)
        let hex = HexTools.hexList(from: data)
        let text = HexTools.textPreview(for: data)
        return (selection.length > UInt64(previewLength) ? "\(hex) …" : hex,
                selection.length > UInt64(previewLength) ? "\(text)…" : text)
    }

    func byteArrayCopy() -> HFByteArray {
        guard let copiedArray = controller.byteArray.copy() as? HFByteArray else {
            let empty = HFBTreeByteArray()
            return empty
        }
        return copiedArray
    }

    func dataForSelection(maxBytes: Int) -> Data {
        let selection = currentSelectionRange()
        guard selection.length > 0 else { return Data() }
        let limitedLength = min(Int(selection.length), maxBytes)
        return data(in: HFRangeMake(selection.location, UInt64(limitedLength)))
    }

    private func configureRepresenters() {
        layoutRepresenter.maximizesBytesPerLine = false

        lineCountingRepresenter.minimumDigitCount = 8
        lineCountingRepresenter.lineNumberFormat = HFLineNumberFormat(rawValue: 1)!
        lineCountingRepresenter.interiorShadowEdge = Int(NSRectEdge.maxX.rawValue)

        statusRepresenter.statusMode = HFStatusBarMode(rawValue: 1)!

        textRepresenter.encoding = HFEncodingManager.shared().ascii

        let alternatingRows = [
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedRed: 0.1, green: 0.11, blue: 0.14, alpha: 1)
                    : NSColor(calibratedRed: 0.99, green: 0.99, blue: 1, alpha: 1)
            },
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1)
                    : NSColor(calibratedRed: 0.95, green: 0.98, blue: 1, alpha: 1)
            }
        ]

        hexRepresenter.rowBackgroundColors = alternatingRows
        textRepresenter.rowBackgroundColors = alternatingRows

        controller.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        hexRepresenter.view().autoresizingMask = [.width, .height]
        textRepresenter.view().autoresizingMask = [.width, .height]
        lineCountingRepresenter.view().autoresizingMask = [.height]
        scrollerRepresenter.view().autoresizingMask = [.height]
        statusRepresenter.view().autoresizingMask = [.width]
    }

    private func configureController() {
        controller.editable = true
        controller.savable = true
        controller.editMode = HFEditMode(rawValue: 1)!
        _ = controller.setBytesPerColumn(4)
        controller.inactiveSelectionColorMatchesActive = true

        controller.addRepresenter(layoutRepresenter)
        controller.addRepresenter(lineCountingRepresenter)
        controller.addRepresenter(hexRepresenter)
        controller.addRepresenter(textRepresenter)
        controller.addRepresenter(scrollerRepresenter)
        controller.addRepresenter(statusRepresenter)

        layoutRepresenter.addRepresenter(lineCountingRepresenter)
        layoutRepresenter.addRepresenter(hexRepresenter)
        layoutRepresenter.addRepresenter(textRepresenter)
        layoutRepresenter.addRepresenter(scrollerRepresenter)
        layoutRepresenter.addRepresenter(statusRepresenter)
    }

    private func configureRootView() {
        let layoutView = layoutRepresenter.view()
        layoutView.frame = rootView.bounds
        layoutView.autoresizingMask = [.width, .height]
        rootView.addSubview(layoutView)
    }

    private func installNotificationObserver() {
        controllerObserver = NotificationCenter.default.addObserver(
            forName: .HFControllerDidChangeProperties,
            object: controller,
            queue: .main
        ) { [weak self] notification in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let changedBits = (notification.userInfo?[HFControllerChangedPropertiesKey] as? NSNumber)?.uintValue ?? 0
                let properties = HFControllerPropertyBits(rawValue: changedBits)

                if properties.contains(.selectedRanges) {
                    self.applySelectionChange()
                }

                if properties.intersection([.contentValue, .contentLength, .editable]).isEmpty == false {
                    self.applyDocumentChange()
                    self.applySelectionChange()
                }
            }
        }
    }

    private func currentSelectionRange() -> HFRange {
        guard let selection = controller.selectedContentsRanges.first?.hfRange() else {
            return HFRangeMake(0, 0)
        }
        return selection
    }

    private func applySelection(_ range: HFRange) {
        isApplyingSelection = true
        controller.selectedContentsRanges = [HFRangeWrapper.withRange(range)]
        isApplyingSelection = false
        applySelectionChange()
    }

    private func applySelectionChange() {
        guard isApplyingSelection == false else { return }
        let selection = currentSelectionRange()
        let previewLength = min(Int(selection.length), previewByteLimit)
        let previewRange = HFRangeMake(selection.location, UInt64(previewLength))
        let previewData = previewLength > 0 ? data(in: previewRange) : Data()

        onSelectionChange?(
            SelectionState(
                start: selection.length == 0 && selection.location >= controller.contentsLength()
                    ? min(byteCount, Int(clamping: selection.location))
                    : Int(clamping: selection.location),
                length: Int(clamping: selection.length),
                previewData: previewData,
                previewIsTruncated: selection.length > UInt64(previewLength),
                totalLength: byteCount
            )
        )
    }

    private func applyDocumentChange() {
        onDocumentChange?(
            DocumentState(
                byteCount: byteCount,
                isDirty: isDirty,
                isEditable: controller.editable
            )
        )
    }

    private func data(in range: HFRange) -> Data {
        guard range.length > 0 else { return Data() }
        let length = Int(clamping: range.length)
        var buffer = Data(count: length)
        buffer.withUnsafeMutableBytes { bytes in
            guard let destination = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            controller.byteArray.copyBytes(destination, range: range)
        }
        return buffer
    }
}
