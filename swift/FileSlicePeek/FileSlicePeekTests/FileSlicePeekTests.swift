//
//  FileSlicePeekTests.swift
//  FileSlicePeekTests
//
//  Created by Andrew Smith on 4/7/26.
//

import Foundation
import Testing
@testable import FileSlicePeek

struct FileSlicePeekTests {
    @Test func parsesHexInputWithSeparators() throws {
        let data = try HexTools.parseSearchInput("89 50 4E 47", mode: .hex)
        #expect(Array(data) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func parsesTextSearchAsUtf8() throws {
        let data = try HexTools.parseSearchInput("Open", mode: .text)
        #expect(String(decoding: data, as: UTF8.self) == "Open")
    }

    @Test func parsesOffsetsInHexAndDecimal() throws {
        #expect(try HexTools.parseOffset("42") == 42)
        #expect(try HexTools.parseOffset("0x2A") == 42)
        #expect(try HexTools.parseOffset("$2A") == 42)
        #expect(try HexTools.parseOffset("2Ah") == 42)
    }

    @Test func buildsReadableHexDump() {
        let dump = HexTools.hexDump(for: Data([0x41, 0x42, 0x43]))
        #expect(dump.contains("00000000"))
        #expect(dump.contains("41 42 43"))
        #expect(dump.contains("ABC"))
    }
}
