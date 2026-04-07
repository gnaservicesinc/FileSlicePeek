import Combine
import Foundation

final class HexDocumentModel: ObservableObject {
    @Published var activeTab: InspectorTab = .info
    @Published var searchMode: SearchMode = .hex
    @Published var findQuery = ""
    @Published var replaceQuery = ""
    @Published var jumpQuery = ""
    @Published var selectionLength = 1 {
        didSet {
            guard selectionLength != oldValue else { return }
            normalizeSelection()
            selectionRefreshToken += 1
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
    @Published private(set) var rowCount = 0
    @Published private(set) var statusText = "Drop a file or choose one to begin."
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectionStart: Int?
    @Published private(set) var selectionRefreshToken = 0
    @Published private(set) var contentRefreshToken = 0

    private let workerQueue = DispatchQueue(label: "fileslicepeek.worker", qos: .userInitiated)
    private let utilityQueue = DispatchQueue(label: "fileslicepeek.utility", qos: .utility)

    private var sourceURL: URL?
    private var originalData = Data()
    private var workingData = Data()
    private var base64Cache: String?
    private var loadRequestID = UUID()
    private var refreshRequestID = UUID()

    var fileName: String {
        hasFile ? displayName : "FileSlicePeek"
    }

    var windowTitle: String {
        hasFile ? "\(displayName)\(isDirty ? " *" : "")" : "FileSlicePeek"
    }

    var dataCount: Int {
        workingData.count
    }

    var dataSnapshot: Data {
        workingData
    }

    var selectionSnapshotKey: String {
        "\(selectionStart ?? -1)-\(selectionLength)-\(selectionRefreshToken)"
    }

    var selectionDescription: String {
        guard let range = selectionRange else {
            return "No selection"
        }

        let lower = HexTools.formatOffset(range.lowerBound, dataCount: max(workingData.count, 1))
        let upper = HexTools.formatOffset(max(range.upperBound - 1, range.lowerBound), dataCount: max(workingData.count, 1))
        return "\(lower) → \(upper) (\(range.count) byte\(range.count == 1 ? "" : "s"))"
    }

    var selectedHexText: String {
        guard let range = selectionRange else { return "" }
        return HexTools.hexList(from: workingData[range])
    }

    var selectedTextText: String {
        guard let range = selectionRange else { return "" }
        return String(decoding: workingData[range], as: UTF8.self)
    }

    var selectedVisibleText: String {
        guard let range = selectionRange else { return "" }
        return HexTools.textPreview(for: Data(workingData[range]))
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
                let data = try Data(contentsOf: resolvedURL, options: [.mappedIfSafe])
                let metadata = HexTools.fileMetadata(for: sourceURL, resolvedURL: resolvedURL, dataSize: data.count)

                DispatchQueue.main.async {
                    guard self.loadRequestID == requestID else { return }

                    self.sourceURL = sourceURL
                    self.originalData = data
                    self.workingData = data
                    self.metadata = metadata
                    self.displayName = metadata.displayName
                    self.visiblePath = metadata.visiblePath
                    self.breadcrumbItems = metadata.visiblePath.split(separator: "/").map(String.init)
                    self.hasFile = true
                    self.isLoading = false
                    self.isDirty = false
                    self.base64Cache = nil
                    self.base64IsReady = false
                    self.rowCount = self.makeRowCount(for: data.count)
                    self.selectionStart = data.isEmpty ? nil : 0
                    self.selectionLength = data.isEmpty ? 0 : 1
                    self.jumpQuery = "0x0"
                    self.activeTab = .info
                    self.statusText = "Loaded \(metadata.displayName) (\(metadata.sizeDescription))."
                    self.contentRefreshToken += 1
                    self.selectionRefreshToken += 1
                    self.scheduleHashRefresh()
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

    func selectByte(at offset: Int) {
        guard workingData.indices.contains(offset) else { return }
        selectionStart = offset
        selectionLength = 1
        jumpQuery = "0x" + String(offset, radix: 16, uppercase: true)
        selectionRefreshToken += 1
    }

    func selectRange(start: Int, length: Int = 1) {
        guard workingData.indices.contains(start) else { return }
        selectionStart = start
        selectionLength = max(length, 1)
        normalizeSelection()
        jumpQuery = "0x" + String(start, radix: 16, uppercase: true)
        selectionRefreshToken += 1
    }

    func isSelected(offset: Int) -> Bool {
        guard let range = selectionRange else { return false }
        return range.contains(offset)
    }

    func hexValue(at offset: Int) -> String {
        guard workingData.indices.contains(offset) else { return "" }
        return HexTools.formatHexByte(workingData[offset])
    }

    func textValue(at offset: Int) -> String {
        guard workingData.indices.contains(offset) else { return "" }
        return HexTools.printableCharacter(for: workingData[offset])
    }

    func byteValue(at offset: Int) -> UInt8? {
        guard workingData.indices.contains(offset) else { return nil }
        return workingData[offset]
    }

    func row(at index: Int) -> HexEditorRow {
        let base = index * HexTools.bytesPerRow
        let upperBound = min(base + HexTools.bytesPerRow, workingData.count)
        let bytes = Array(workingData[base..<upperBound])
        return HexEditorRow(index: index, baseOffset: base, bytes: bytes)
    }

    func saveFile() {
        guard let sourceURL else {
            statusText = "Open a file first."
            return
        }

        workerQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.workingData

            do {
                try snapshot.write(to: sourceURL, options: .atomic)
                DispatchQueue.main.async {
                    self.originalData = snapshot
                    self.isDirty = false
                    self.statusText = "Saved \(self.displayName)."
                    self.scheduleHashRefresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentError(error)
                }
            }
        }
    }

    func revertChanges() {
        guard hasFile else { return }
        workingData = originalData
        isDirty = false
        rowCount = makeRowCount(for: workingData.count)
        normalizeSelection()
        base64Cache = nil
        base64IsReady = false
        statusText = "Reverted unsaved changes."
        contentRefreshToken += 1
        selectionRefreshToken += 1
        scheduleHashRefresh()
    }

    func moveSelection() {
        do {
            let offset = try HexTools.parseOffset(jumpQuery)
            guard workingData.indices.contains(offset) else {
                throw HexUtilityError.invalidOffset(jumpQuery)
            }

            selectionStart = offset
            normalizeSelection()
            statusText = "Moved selection to \(HexTools.formatOffset(offset, dataCount: max(workingData.count, 1)))."
            selectionRefreshToken += 1
        } catch {
            presentError(error)
        }
    }

    func applyHexEdit(_ value: String) {
        do {
            let replacement = try HexTools.parseReplacementInput(value, mode: .hex)
            try replaceSelection(with: replacement, message: "Updated selection using hex bytes.")
        } catch {
            presentError(error)
        }
    }

    func applyTextEdit(_ value: String) {
        do {
            let replacement = try HexTools.parseReplacementInput(value, mode: .text)
            try replaceSelection(with: replacement, message: "Updated selection using text.")
        } catch {
            presentError(error)
        }
    }

    @discardableResult
    func replaceHexInput(_ value: String, at offset: Int, replacing length: Int = 1) -> Int? {
        guard workingData.indices.contains(offset) else { return nil }

        do {
            let replacement = try HexTools.parseReplacementInput(value, mode: .hex)
            return replaceBytes(at: offset, length: length, with: replacement, message: "Updated bytes from the hex view.")
        } catch {
            presentError(error)
            return nil
        }
    }

    @discardableResult
    func replaceTextInput(_ value: String, at offset: Int, replacing length: Int = 1) -> Int? {
        guard workingData.indices.contains(offset) else { return nil }

        do {
            let replacement = try HexTools.parseReplacementInput(value, mode: .text)
            return replaceBytes(at: offset, length: length, with: replacement, message: "Updated bytes from the text view.")
        } catch {
            presentError(error)
            return nil
        }
    }

    @discardableResult
    func findNext() -> Bool {
        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            return selectMatch(pattern: pattern, direction: .forward)
        } catch {
            presentError(error)
            return false
        }
    }

    @discardableResult
    func findPrevious() -> Bool {
        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            return selectMatch(pattern: pattern, direction: .backward)
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

            var data = workingData
            var cursor = data.startIndex
            var replacements = 0
            var lastReplacementRange: Range<Int>?

            while cursor <= data.endIndex {
                guard let range = data.range(of: pattern, options: [], in: cursor..<data.endIndex) else {
                    break
                }

                data.replaceSubrange(range, with: replacement)
                lastReplacementRange = range.lowerBound..<(range.lowerBound + replacement.count)
                cursor = range.lowerBound + replacement.count
                replacements += 1
            }

            guard replacements > 0 else {
                statusText = "No matches were replaced."
                return
            }

            workingData = data
            if let lastReplacementRange {
                selectionStart = lastReplacementRange.lowerBound
                selectionLength = max(lastReplacementRange.count, 1)
            }

            markBufferChanged(message: "Replaced \(replacements) match\(replacements == 1 ? "" : "es").")
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
        guard hash != "—", hash != "Computing…" else {
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
        guard selectionRange != nil else {
            statusText = "Select bytes first."
            return
        }

        switch mode {
        case .hex:
            AppKitPanels.copyToPasteboard(selectedHexText)
            statusText = "Copied hex bytes."
        case .text:
            AppKitPanels.copyToPasteboard(selectedVisibleText)
            statusText = "Copied text bytes."
        }
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

    private enum SearchDirection {
        case forward
        case backward
    }

    private var selectionRange: Range<Int>? {
        guard let selectionStart else { return nil }
        guard workingData.isEmpty == false, workingData.indices.contains(selectionStart) else { return nil }
        let clampedLength = max(1, min(selectionLength, workingData.count - selectionStart))
        return selectionStart..<(selectionStart + clampedLength)
    }

    private func makeRowCount(for byteCount: Int) -> Int {
        max(1, Int(ceil(Double(max(byteCount, 1)) / Double(HexTools.bytesPerRow))))
    }

    private func normalizeSelection() {
        guard workingData.isEmpty == false else {
            selectionStart = nil
            selectionLength = 0
            return
        }

        if selectionStart == nil {
            selectionStart = 0
        }

        if let selectionStart, selectionStart >= workingData.count {
            self.selectionStart = max(workingData.count - 1, 0)
        }

        if selectionLength <= 0 {
            selectionLength = 1
        }

        if let selectionStart {
            selectionLength = min(max(selectionLength, 1), workingData.count - selectionStart)
        }
    }

    private func replaceCurrent(andAdvance: Bool) {
        guard hasFile else { return }

        do {
            let pattern = try HexTools.parseSearchInput(findQuery, mode: searchMode)
            let replacement = try HexTools.parseReplacementInput(replaceQuery, mode: searchMode)

            guard matchIsSelected(pattern: pattern) || selectMatch(pattern: pattern, direction: .forward) else {
                statusText = "No current match to replace."
                return
            }

            guard let range = selectionRange else { return }
            workingData.replaceSubrange(range, with: replacement)
            selectionStart = min(range.lowerBound, max(workingData.count - 1, 0))
            selectionLength = max(replacement.count, 1)
            markBufferChanged(message: "Replaced the current match.")

            if andAdvance {
                _ = selectMatch(pattern: pattern, direction: .forward)
            }
        } catch {
            presentError(error)
        }
    }

    private func matchIsSelected(pattern: Data) -> Bool {
        guard let range = selectionRange, range.count == pattern.count else { return false }
        return workingData[range] == pattern[pattern.startIndex..<pattern.endIndex]
    }

    private func selectMatch(pattern: Data, direction: SearchDirection) -> Bool {
        guard workingData.isEmpty == false else {
            statusText = "Open a file first."
            return false
        }

        let matchRange: Range<Int>?

        switch direction {
        case .forward:
            let start = min(selectionRange?.upperBound ?? 0, workingData.endIndex)
            matchRange = workingData.range(of: pattern, options: [], in: start..<workingData.endIndex)
                ?? workingData.range(of: pattern, options: [], in: 0..<start)
        case .backward:
            let end = min(selectionRange?.lowerBound ?? workingData.endIndex, workingData.endIndex)
            matchRange = workingData.range(of: pattern, options: [.backwards], in: 0..<end)
                ?? workingData.range(of: pattern, options: [.backwards], in: end..<workingData.endIndex)
        }

        guard let matchRange else {
            statusText = "No matches found."
            return false
        }

        selectionStart = matchRange.lowerBound
        selectionLength = max(matchRange.count, 1)
        jumpQuery = "0x" + String(matchRange.lowerBound, radix: 16, uppercase: true)
        statusText = "Match at \(HexTools.formatOffset(matchRange.lowerBound, dataCount: max(workingData.count, 1)))."
        selectionRefreshToken += 1
        activeTab = .editor
        return true
    }

    private func replaceSelection(with replacement: Data, message: String) throws {
        guard let range = selectionRange else {
            throw HexUtilityError.emptyInput
        }

        workingData.replaceSubrange(range, with: replacement)
        selectionStart = min(range.lowerBound, max(workingData.count - 1, 0))
        selectionLength = max(replacement.count, 1)
        markBufferChanged(message: message)
    }

    @discardableResult
    private func replaceBytes(at offset: Int, length: Int, with replacement: Data, message: String) -> Int {
        guard workingData.indices.contains(offset) else { return 0 }

        let actualLength = max(0, min(length, workingData.count - offset))
        let range = offset..<(offset + actualLength)
        workingData.replaceSubrange(range, with: replacement)
        selectionStart = min(offset, max(workingData.count - 1, 0))
        selectionLength = max(replacement.count, 1)
        markBufferChanged(message: message)
        return replacement.count
    }

    private func exportText(kind: ExportKind) {
        guard hasFile else {
            statusText = "Open a file first."
            return
        }

        let suggestedName: String
        let generator: (Data) -> String

        switch kind {
        case .hexDump:
            suggestedName = "\(displayName).hex.txt"
            generator = HexTools.hexDump(for:)
        case .textPreview:
            suggestedName = "\(displayName).txt"
            generator = HexTools.decodedText(for:)
        case .base64:
            suggestedName = "\(displayName).base64.txt"
            generator = { $0.base64EncodedString() }
        }

        guard let destination = AppKitPanels.chooseExportURL(suggestedName: suggestedName, pathExtension: "txt") else {
            return
        }

        let snapshot = workingData
        utilityQueue.async { [weak self] in
            guard let self else { return }

            do {
                let output = generator(snapshot)
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
    }

    private func requestBase64(_ completion: @escaping (String) -> Void) {
        if let base64Cache {
            completion(base64Cache)
            return
        }

        let snapshot = workingData
        statusText = "Preparing Base64…"

        utilityQueue.async { [weak self] in
            guard let self else { return }
            let encoded = snapshot.base64EncodedString()

            DispatchQueue.main.async {
                self.base64Cache = encoded
                self.base64IsReady = true
                completion(encoded)
            }
        }
    }

    private func markBufferChanged(message: String) {
        isDirty = true
        rowCount = makeRowCount(for: workingData.count)
        base64Cache = nil
        base64IsReady = false
        normalizeSelection()
        statusText = message
        contentRefreshToken += 1
        selectionRefreshToken += 1
        scheduleHashRefresh()
    }

    private func scheduleHashRefresh() {
        let requestID = UUID()
        refreshRequestID = requestID
        let snapshot = workingData
        hashes = HashSummary.loading

        utilityQueue.async { [weak self] in
            guard let self else { return }
            let summary = HexTools.hashSummary(for: snapshot)

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
