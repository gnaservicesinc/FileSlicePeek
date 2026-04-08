import CryptoKit
import Foundation
import HexFiend

enum SearchMode: String, CaseIterable, Identifiable {
    case hex
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hex:
            return "Hex"
        case .text:
            return "Text"
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case info
    case editor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info:
            return "Info & Hashes"
        case .editor:
            return "Hex Editor"
        }
    }
}

enum HexUtilityError: LocalizedError {
    case emptyInput
    case invalidHex(String)
    case invalidOffset(String)
    case operationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a value first."
        case let .invalidHex(value):
            return "\"\(value)\" is not valid hex. Use pairs like 4F 2A."
        case let .invalidOffset(value):
            return "\"\(value)\" is not a valid offset."
        case let .operationUnavailable(message):
            return message
        }
    }
}

struct HashSummary {
    let md5: String
    let sha1: String
    let sha256: String

    static let loading = HashSummary(md5: "Computing…", sha1: "Computing…", sha256: "Computing…")
    static let empty = HashSummary(md5: "—", sha1: "—", sha256: "—")
}

struct FileMetadataSnapshot {
    let resolvedURL: URL?
    let displayName: String
    let visiblePath: String
    let sizeDescription: String
    let owner: String
    let group: String
    let created: String
    let modified: String
    let kindDescription: String

    static let empty = FileMetadataSnapshot(
        resolvedURL: nil,
        displayName: "FileSlicePeek",
        visiblePath: "",
        sizeDescription: "—",
        owner: "—",
        group: "—",
        created: "—",
        modified: "—",
        kindDescription: "No file loaded"
    )
}

enum ExportKind {
    case hexDump
    case textPreview
    case base64
}

enum ByteEditorMode: Hashable {
    case hex
    case text
}

enum HexTools {
    nonisolated static let bytesPerRow = 16

    nonisolated static func parseSearchInput(_ rawValue: String, mode: SearchMode) throws -> Data {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .hex:
            return try parseHex(trimmed, allowEmpty: false)
        case .text:
            guard trimmed.isEmpty == false else {
                throw HexUtilityError.emptyInput
            }
            return Data(trimmed.utf8)
        }
    }

    nonisolated static func parseReplacementInput(_ rawValue: String, mode: SearchMode) throws -> Data {
        switch mode {
        case .hex:
            return try parseHex(rawValue, allowEmpty: true)
        case .text:
            return Data(rawValue.utf8)
        }
    }

    nonisolated static func parseHex(_ rawValue: String, allowEmpty: Bool) throws -> Data {
        let filtered = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "$", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()

        guard filtered.isEmpty == false else {
            if allowEmpty {
                return Data()
            }
            throw HexUtilityError.emptyInput
        }

        guard filtered.count.isMultiple(of: 2) else {
            throw HexUtilityError.invalidHex(rawValue)
        }

        var data = Data(capacity: filtered.count / 2)
        var cursor = filtered.startIndex

        while cursor < filtered.endIndex {
            let next = filtered.index(cursor, offsetBy: 2)
            let pair = String(filtered[cursor..<next])

            guard let byte = UInt8(pair, radix: 16) else {
                throw HexUtilityError.invalidHex(rawValue)
            }

            data.append(byte)
            cursor = next
        }

        return data
    }

    nonisolated static func parseOffset(_ rawValue: String) throws -> Int {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false else {
            throw HexUtilityError.emptyInput
        }

        let normalized = trimmed.lowercased()

        if normalized.hasPrefix("0x") {
            guard let value = Int(normalized.dropFirst(2), radix: 16) else {
                throw HexUtilityError.invalidOffset(rawValue)
            }
            return value
        }

        if normalized.hasPrefix("$") {
            guard let value = Int(normalized.dropFirst(), radix: 16) else {
                throw HexUtilityError.invalidOffset(rawValue)
            }
            return value
        }

        if normalized.hasSuffix("h") {
            guard let value = Int(normalized.dropLast(), radix: 16) else {
                throw HexUtilityError.invalidOffset(rawValue)
            }
            return value
        }

        if normalized.range(of: #"[a-f]"#, options: .regularExpression) != nil {
            guard let value = Int(normalized, radix: 16) else {
                throw HexUtilityError.invalidOffset(rawValue)
            }
            return value
        }

        guard let value = Int(normalized) else {
            throw HexUtilityError.invalidOffset(rawValue)
        }

        return value
    }

    nonisolated static func formatHexByte(_ byte: UInt8) -> String {
        String(format: "%02X", byte)
    }

    nonisolated static func formatOffset(_ offset: Int, dataCount: Int) -> String {
        let addressWidth = max(8, String(max(dataCount - 1, 0), radix: 16).count)
        return String(format: "%0*X", addressWidth, offset)
    }

    nonisolated static func printableCharacter(for byte: UInt8) -> String {
        switch byte {
        case 32...126:
            return String(UnicodeScalar(byte))
        case 9:
            return "⇥"
        case 10:
            return "↩"
        case 13:
            return "␍"
        default:
            return "·"
        }
    }

    nonisolated static func hexList(from bytes: some Sequence<UInt8>) -> String {
        bytes.map(formatHexByte).joined(separator: " ")
    }

    nonisolated static func textPreview(for data: Data) -> String {
        String(data.map { printableCharacter(for: $0) }.joined())
    }

    nonisolated static func decodedText(for data: Data) -> String {
        textPreview(for: data)
    }

    nonisolated static func hexDump(for data: Data) -> String {
        guard data.isEmpty == false else {
            return "00000000"
        }

        var lines: [String] = []
        lines.reserveCapacity((data.count / bytesPerRow) + 1)
        let bytes = Array(data)

        for rowIndex in stride(from: 0, to: bytes.count, by: bytesPerRow) {
            let rowBytes = Array(bytes[rowIndex..<min(rowIndex + bytesPerRow, bytes.count)])
            let hexColumns = rowBytes.map(formatHexByte)
            let paddedHex = hexColumns + Array(repeating: "  ", count: max(0, bytesPerRow - rowBytes.count))
            let ascii = rowBytes.map(printableCharacter).joined()
            let paddedASCII = ascii.padding(toLength: bytesPerRow, withPad: " ", startingAt: 0)
            let address = formatOffset(rowIndex, dataCount: data.count)
            lines.append("\(address)  \(paddedHex.joined(separator: " "))  \(paddedASCII)")
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func hashSummary(for data: Data) -> HashSummary {
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return HashSummary(md5: md5, sha1: sha1, sha256: sha256)
    }

    nonisolated static func hashSummary(for byteArray: HFByteArray, chunkSize: Int = 1 << 20) -> HashSummary {
        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()

        enumerateChunks(in: byteArray, chunkSize: chunkSize) { chunk in
            md5.update(data: chunk)
            sha1.update(data: chunk)
            sha256.update(data: chunk)
        }

        return HashSummary(
            md5: md5.finalize().map { String(format: "%02x", $0) }.joined(),
            sha1: sha1.finalize().map { String(format: "%02x", $0) }.joined(),
            sha256: sha256.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    nonisolated static func fileMetadata(for sourceURL: URL, resolvedURL: URL) -> FileMetadataSnapshot {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let attributes = (try? FileManager.default.attributesOfItem(atPath: resolvedURL.path)) ?? [:]
        let createdDate = attributes[.creationDate] as? Date
        let modifiedDate = attributes[.modificationDate] as? Date
        let owner = (attributes[.ownerAccountName] as? String) ?? "Unknown"
        let group = (attributes[.groupOwnerAccountName] as? String) ?? "Unknown"
        let dataSize = (attributes[.size] as? NSNumber)?.intValue ?? 0

        let kindDescription: String
        if sourceURL.pathExtension.lowercased() == "app", let bundle = Bundle(url: sourceURL), let executableURL = bundle.executableURL {
            kindDescription = "Application bundle executable (\(executableURL.lastPathComponent))"
        } else if sourceURL.pathExtension.isEmpty == false {
            kindDescription = "\(sourceURL.pathExtension.uppercased()) file"
        } else {
            kindDescription = "Binary data"
        }

        return FileMetadataSnapshot(
            resolvedURL: resolvedURL,
            displayName: sourceURL.lastPathComponent,
            visiblePath: sourceURL.path,
            sizeDescription: formatter.string(fromByteCount: Int64(dataSize)),
            owner: owner,
            group: group,
            created: createdDate.map(dateFormatter.string(from:)) ?? "—",
            modified: modifiedDate.map(dateFormatter.string(from:)) ?? "—",
            kindDescription: kindDescription
        )
    }

    nonisolated static func byteArray(from data: Data) -> HFByteArray {
        let byteSlice = HFFullMemoryByteSlice(data: data)
        let byteArray = HFBTreeByteArray()
        byteArray.insertByteSlice(byteSlice, in: HFRangeMake(0, 0))
        return byteArray
    }

    nonisolated static func data(from byteArray: HFByteArray, maxBytes: Int? = nil) -> Data {
        let totalLength = Int(clamping: byteArray.length())
        let length = min(maxBytes ?? totalLength, totalLength)
        guard length > 0 else { return Data() }

        var data = Data(count: length)
        data.withUnsafeMutableBytes { bytes in
            guard let destination = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            byteArray.copyBytes(destination, range: HFRangeMake(0, UInt64(length)))
        }
        return data
    }

    nonisolated static func enumerateChunks(in byteArray: HFByteArray, chunkSize: Int = 1 << 20, using block: (Data) -> Void) {
        let totalLength = Int(clamping: byteArray.length())
        guard totalLength > 0 else { return }

        var offset = 0
        while offset < totalLength {
            let length = min(chunkSize, totalLength - offset)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { bytes in
                guard let destination = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
                byteArray.copyBytes(destination, range: HFRangeMake(UInt64(offset), UInt64(length)))
            }
            block(data)
            offset += length
        }
    }

    nonisolated static func resolveInspectableURL(_ sourceURL: URL) throws -> URL {
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isDirectory = values.isDirectory ?? false

        if isDirectory == false {
            return sourceURL
        }

        if sourceURL.pathExtension.lowercased() == "app", let bundle = Bundle(url: sourceURL), let executableURL = bundle.executableURL {
            return executableURL
        }

        throw CocoaError(.fileReadUnsupportedScheme, userInfo: [
            NSLocalizedDescriptionKey: "Directories cannot be inspected directly. Choose a file or application bundle."
        ])
    }
}
