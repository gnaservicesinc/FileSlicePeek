import AppKit
import Combine
import Foundation

@MainActor
final class HexDocumentModel: ObservableObject {
    @Published var activeTab: InspectorTab = .info
    @Published var searchMode: SearchMode = .hex
    @Published var findQuery = ""
    @Published var replaceQuery = ""
    @Published var jumpQuery = ""
    @Published var selectionLength = 0 {
        didSet {
            guard selectionLength != oldValue else { return }
            guard isApplyingEditorSelection == false else { return }
            applySelectionLengthChange()
        }
    }

    @Published private(set) var hasFile = false
    @Published private(set) var isLoading = false
    @Published private(set) var isDirty = false
    @Published private(set) var displayName = "FileSlicePeek"
    @Published private(set) var visiblePath = ""
    @Published private(set) var breadcrumbItems: [String] = []
    @Published private(set) var metadata = FileMetadataSnapshot.empty
    @Published private(set) var hashes = HashSummary.empty
    @Published private(set) var base64IsReady = false
    @Published private(set) var statusText = "Drop a file or choose one to begin."
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectionStart: Int?
    @Published private(set) var selectionRefreshToken = 0

    private let workerQueue = DispatchQueue(label: "fileslicepeek.worker", qos: .userInitiated)
    private let utilityQueue = DispatchQueue(label: "fileslicepeek.utility", qos: .utility)
    private let editorSession = HexFiendEditorSession()
    private let selectionPreviewLimit = 256
    private let helperDataLimit = 32 * 1024 * 1024

    private var sourceURL: URL?
    private var resolvedURL: URL?
    private var base64Cache: String?
    private var loadRequestID = UUID()
    private var refreshRequestID = UUID()
    private var byteCount = 0
    private var selectedHexPreview = ""
    private var selectedTextPreview = ""
    private var isApplyingEditorSelection = false

    init() {
        editorSession.onSelectionChange = { [weak self] state in
            self?.applyEditorSelection(state)
        }

        editorSession.onDocumentChange = { [weak self] state in
            self?.applyEditorDocumentState(state)
        }
    }

    var fileName: String {
        hasFile ? displayName : "FileSlicePeek"
    }

    var windowTitle: String {
        hasFile ? "\(displayName)\(isDirty ? " *" : "")" : "FileSlicePeek"
    }

    var dataCount: Int {
        byteCount
    }

    var selectionSnapshotKey: String {
        "\(selectionStart ?? -1)-\(selectionLength)-\(selectionRefreshToken)"
    }

    var selectionDescription: String {
        guard let selectionStart else {
            return "No selection"
        }

        let safeCount = max(byteCount, 1)
        if selectionLength == 0 {
            let offset = HexTools.formatOffset(selectionStart, dataCount: safeCount)
            return "Cursor at \(offset)"
        }

        let lower = HexTools.formatOffset(selectionStart, dataCount: safeCount)
        let upper = HexTools.formatOffset(max(selectionStart + selectionLength - 1, selectionStart), dataCount: safeCount)
        return "\(lower) → \(upper) (\(selectionLength) byte\(selectionLength == 1 ? "" : "s"))"
    }

    var selectedHexText: String {
        selectedHexPreview
    }

    var selectedTextText: String {
        selectedTextPreview
    }

    var selectedVisibleText: String {
        selectedTextPreview
    }

    var editorView: NSView {
        editorSession.mountedView
    }

    func dismissError() {
        errorMessage = nil
    }

    func openFile(at sourceURL: URL) {
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        errorMessage = nil
        statusText = "Opening \(sourceURL.lastPathComponent)…"

        workerQueue.async { [weak self] in
            guard let self else { return }

            do {
                let resolvedURL = try HexTools.resolveInspectableURL(sourceURL)
                let metadata = HexTools.fileMetadata(for: sourceURL, resolvedURL: resolvedURL)

                DispatchQueue.main.async {
                    guard self.loadRequestID == requestID else { return }

                    do {
                        try self.editorSession.loadDocument(at: resolvedURL)
                        self.sourceURL = sourceURL
                        self.resolvedURL = resolvedURL
                        self.metadata = metadata
                        self.displayName = metadata.displayName
                        self.visiblePath = metadata.visiblePath
                        self.breadcrumbItems = metadata.visiblePath.split(separator: "/").map(String.init)
                        self.hasFile = true
                        self.isLoading = false
                        self.base64Cache = nil
                        self.base64IsReady = false
                        self.jumpQuery = "0x0"
                        self.activeTab = .editor
                        self.statusText = "Loaded \(metadata.displayName) (\(metadata.sizeDescription))."
                        self.scheduleHashRefresh()
                    } catch {
                        self.isLoading = false
                        self.presentError(error)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.loadRequestID == requestID else { return }
                    self.isLoading = false
                    self.presentError(error)
                }
            }
        }
    }

    func saveFile() {
        guard hasFile else {
            statusText = "Open a file first."
            return
        }

        do {
            try editorSession.saveDocument()
            statusText = "Saved \(displayName)."
            scheduleHashRefresh()
        } catch {
            presentError(error)
        }
    }

    func revertChanges() {
        guard hasFile else { return }

        do {
            try editorSession.revertDocument()
            base64Cache = nil
            base64IsReady = false
            statusText = "Reverted unsaved changes."
            scheduleHashRefresh()
        } catch {
            presentError(error)
        }
    }

    func moveSelection() {
        do {
            let offset = try HexTools.parseOffset(jumpQuery)
            guard byteCount > 0, offset < byteCount else {
                throw HexUtilityError.invalidOffset(jumpQuery)
            }

            editorSession.selectRange(start: offset, length: selectionLength)
            statusText = "Moved selection to \(HexTools.formatOffset(offset, dataCount: max(byteCount, 1)))."
        } catch {
            presentError(error)
        }
    }

    func applyHexEdit(_ value: String) {
        do {
            let replacement = try HexTools.parseReplacementInput(value, mode: .hex)
            editorSession.replaceSelection(with: replacement)
            markDirtyState(message: "Updated selection using hex bytes.")
        } catch {
            presentError(error)
        }
    }

    func applyTextEdit(_ value: String) {
        do {
            let replacement = try HexTools.parseReplacementInput(value, mode: .text)
            editorSession.replaceSelection(with: replacement)
            markDirtyState(message: "Updated selection using text.")
        } catch {
            presentError(error)
        }
    }

    @discardableResult
    func findNext() -> Bool {
        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            let found = editorSession.find(pattern: pattern, direction: .forward)
            statusText = found
                ? "Match at \(HexTools.formatOffset(selectionStart ?? 0, dataCount: max(byteCount, 1)))."
                : "No matches found."
            if found {
                activeTab = .editor
            }
            return found
        } catch {
            presentError(error)
            return false
        }
    }

    @discardableResult
    func findPrevious() -> Bool {
        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            let found = editorSession.find(pattern: pattern, direction: .backward)
            statusText = found
                ? "Match at \(HexTools.formatOffset(selectionStart ?? 0, dataCount: max(byteCount, 1)))."
                : "No matches found."
            if found {
                activeTab = .editor
            }
            return found
        } catch {
            presentError(error)
            return false
        }
    }

    func replaceCurrentMatch() {
        replaceCurrent(andAdvance: false)
    }

    func replaceCurrentAndFindNext() {
        replaceCurrent(andAdvance: true)
    }

    func replaceAllMatches() {
        guard hasFile else { return }

        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            let replacement = try HexTools.parseReplacementInput(replaceQuery, mode: searchMode)
            guard pattern.isEmpty == false else {
                throw HexUtilityError.emptyInput
            }

            let replacements = editorSession.replaceAll(pattern: pattern, replacement: replacement)
            if replacements == 0 {
                statusText = "No matches were replaced."
                return
            }

            markDirtyState(message: "Replaced \(replacements) match\(replacements == 1 ? "" : "es").")
        } catch {
            presentError(error)
        }
    }

    func exportHexDump() {
        exportText(kind: .hexDump)
    }

    func exportTextPreview() {
        exportText(kind: .textPreview)
    }

    func copyHash(_ hash: String, label: String) {
        guard hash != "—", hash != "Computing…", hash != "Modified" else {
            statusText = "\(label) is not ready yet."
            return
        }

        AppKitPanels.copyToPasteboard(hash)
        statusText = "Copied \(label)."
    }

    func copyBase64() {
        requestBase64 { base64 in
            AppKitPanels.copyToPasteboard(base64)
            self.statusText = "Copied Base64."
        }
    }

    func copySelection(using mode: ByteEditorMode) {
        let preview = editorSession.selectedPreview()
        let string: String

        switch mode {
        case .hex:
            string = preview.hex
        case .text:
            string = preview.text
        }

        guard string.isEmpty == false else {
            statusText = "Select bytes first."
            return
        }

        AppKitPanels.copyToPasteboard(string)
        statusText = mode == .hex ? "Copied hex bytes." : "Copied text bytes."
    }

    func exportBase64() {
        requestBase64 { base64 in
            guard let destination = AppKitPanels.chooseExportURL(
                suggestedName: "\(self.displayName).base64.txt",
                pathExtension: "txt"
            ) else {
                return
            }

            self.utilityQueue.async {
                do {
                    try base64.write(to: destination, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.statusText = "Saved Base64 to \(destination.lastPathComponent)."
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.presentError(error)
                    }
                }
            }
        }
    }

    private func applyEditorSelection(_ state: HexFiendEditorSession.SelectionState) {
        isApplyingEditorSelection = true
        selectionStart = state.start
        selectionLength = state.length
        isApplyingEditorSelection = false

        selectedHexPreview = HexTools.hexList(from: state.previewData)
        selectedTextPreview = HexTools.textPreview(for: state.previewData)

        if state.previewIsTruncated {
            if selectedHexPreview.isEmpty == false {
                selectedHexPreview += " …"
            }
            if selectedTextPreview.isEmpty == false {
                selectedTextPreview += "…"
            }
        }

        if let selectionStart {
            jumpQuery = "0x" + String(selectionStart, radix: 16, uppercase: true)
        }

        selectionRefreshToken += 1
    }

    private func applyEditorDocumentState(_ state: HexFiendEditorSession.DocumentState) {
        let wasDirty = isDirty
        byteCount = state.byteCount
        isDirty = state.isDirty

        if wasDirty == false, state.isDirty {
            base64Cache = nil
            base64IsReady = false
            hashes = HashSummary(md5: "Modified", sha1: "Modified", sha256: "Modified")
        }
    }

    private func applySelectionLengthChange() {
        guard let selectionStart, byteCount > 0 else { return }
        let clampedLength = min(max(selectionLength, 0), byteCount - min(selectionStart, max(byteCount - 1, 0)))

        if clampedLength != selectionLength {
            isApplyingEditorSelection = true
            selectionLength = clampedLength
            isApplyingEditorSelection = false
        }

        editorSession.selectRange(start: selectionStart, length: clampedLength)
    }

    private func replaceCurrent(andAdvance: Bool) {
        guard hasFile else { return }

        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            let replacement = try HexTools.parseReplacementInput(replaceQuery, mode: searchMode)

            guard editorSession.selectionStartsWith(pattern) || editorSession.find(pattern: pattern, direction: .forward) else {
                statusText = "No current match to replace."
                return
            }

            editorSession.replaceSelection(with: replacement)
            markDirtyState(message: "Replaced the current match.")

            if andAdvance {
                _ = editorSession.find(pattern: pattern, direction: .forward)
            }
        } catch {
            presentError(error)
        }
    }

    private func exportText(kind: ExportKind) {
        guard hasFile else {
            statusText = "Open a file first."
            return
        }

        do {
            let data = try helperSnapshotData()
            let suggestedName: String
            let output: String

            switch kind {
            case .hexDump:
                suggestedName = "\(displayName).hex.txt"
                output = HexTools.hexDump(for: data)
            case .textPreview:
                suggestedName = "\(displayName).txt"
                output = HexTools.decodedText(for: data)
            case .base64:
                suggestedName = "\(displayName).base64.txt"
                output = data.base64EncodedString()
            }

            guard let destination = AppKitPanels.chooseExportURL(suggestedName: suggestedName, pathExtension: "txt") else {
                return
            }

            utilityQueue.async { [weak self] in
                guard let self else { return }

                do {
                    try output.write(to: destination, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.statusText = "Saved \(destination.lastPathComponent)."
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.presentError(error)
                    }
                }
            }
        } catch {
            presentError(error)
        }
    }

    private func requestBase64(_ completion: @escaping (String) -> Void) {
        if let base64Cache {
            completion(base64Cache)
            return
        }

        do {
            let data = try helperSnapshotData()
            statusText = "Preparing Base64…"

            utilityQueue.async { [weak self] in
                guard let self else { return }
                let encoded = data.base64EncodedString()

                DispatchQueue.main.async {
                    self.base64Cache = encoded
                    self.base64IsReady = true
                    completion(encoded)
                }
            }
        } catch {
            presentError(error)
        }
    }

    private func helperSnapshotData() throws -> Data {
        guard byteCount <= helperDataLimit else {
            throw HexUtilityError.operationUnavailable("This helper is limited to files up to \(ByteCountFormatter.string(fromByteCount: Int64(helperDataLimit), countStyle: .file)).")
        }

        let byteArray = editorSession.byteArrayCopy()
        return HexTools.data(from: byteArray)
    }

    private func markDirtyState(message: String) {
        base64Cache = nil
        base64IsReady = false
        hashes = HashSummary(md5: "Modified", sha1: "Modified", sha256: "Modified")
        statusText = message
        selectionRefreshToken += 1
    }

    private func scheduleHashRefresh() {
        guard hasFile else { return }
        if isDirty {
            hashes = HashSummary(md5: "Modified", sha1: "Modified", sha256: "Modified")
            return
        }

        let requestID = UUID()
        refreshRequestID = requestID
        hashes = HashSummary.loading
        let byteArray = editorSession.byteArrayCopy()

        utilityQueue.async { [weak self] in
            guard let self else { return }
            let summary = HexTools.hashSummary(for: byteArray)

            DispatchQueue.main.async {
                guard self.refreshRequestID == requestID else { return }
                self.hashes = summary
            }
        }
    }

    private func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = error.localizedDescription
    }
}
