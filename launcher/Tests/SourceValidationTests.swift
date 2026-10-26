import XCTest
@testable import iSwitchCore

final class SourceValidationTests: XCTestCase {
    func testKeyValidationRejectsConflictsAndPreservesSecretsInErrors() throws {
        let key = String(repeating: "ab", count: 32)
        XCTAssertEqual(try SourceValidation.keyCount(Data("header_key = \(key)\nHEADER_KEY = \(key.uppercased())\nmaster_key_00 = \(String(repeating: "cd", count: 16))\n".utf8)), 2)
        for bad in ["", "header_key=bad", "header_key=\(key)\nheader_key=\(String(repeating: "ef", count: 32))", "header_key=\(key)\nother=$(command)"] {
            XCTAssertThrowsError(try SourceValidation.keyCount(Data(bad.utf8))) { error in XCTAssertFalse(error.localizedDescription.contains(key)) }
        }
        XCTAssertThrowsError(try SourceValidation.keyCount(Data(repeating: 65, count: 256 * 1024 + 1)))
    }

    func testGameMagicAndTitleIDs() throws {
        XCTAssertNoThrow(try SourceValidation.gameHeader(Data("PFS0".utf8), extension: "NSP"))
        var xci = Data(repeating: 0, count: 256); xci.append(Data("HEAD".utf8))
        XCTAssertNoThrow(try SourceValidation.gameHeader(xci, extension: "xci"))
        XCTAssertThrowsError(try SourceValidation.gameHeader(Data("PK00".utf8), extension: "nsp"))
        XCTAssertThrowsError(try SourceValidation.gameHeader(Data("HEAD".utf8), extension: "xci"))
        XCTAssertEqual(SourceValidation.titleID(in: "Wonder [010015100B514800][v65536].nsp"), "010015100B514800")
        XCTAssertNil(SourceValidation.titleID(in: "0010015100B5148000.nsp"))
    }

    func testFirmwareDirectoryRejectsInstallerTraversalEncryptionAndTruncation() throws {
        let name = String(repeating: "a", count: 32) + ".nca"
        let valid = archive(name: "Firmware/" + name)
        try withFile(valid) { url in
            let summary = try FirmwareArchive.inspect(url)
            XCTAssertEqual(summary.archiveCount, 1)
            XCTAssertEqual(summary.expandedBytes, 1024)
        }
        for invalid in [archive(name: "../" + name), archive(name: "/" + name), archive(name: "Setup.exe"), archive(name: name, flags: 1), archive(name: name, mode: 0xa000), Data(valid.dropLast()), archive(name: name, expanded: UInt32.max)] {
            try withFile(invalid) { XCTAssertThrowsError(try FirmwareArchive.inspect($0)) }
        }
    }

    private func withFile(_ data: Data, body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url); try body(url)
    }

    // A stored ZIP fixture with one synthetic NCA. No console content or real keys.
    private func archive(name: String, flags: UInt16 = 0, mode: UInt32 = 0, expanded: UInt32 = 1024) -> Data {
        let path = Data(name.utf8)
        var local = Data(repeating: 0, count: 30)
        put32(0x04034b50, into: &local, at: 0); put16(UInt16(path.count), into: &local, at: 26)
        local.append(path); local.append(Data(repeating: 0, count: 1024))
        var central = Data(repeating: 0, count: 46)
        put32(0x02014b50, into: &central, at: 0); put16(flags, into: &central, at: 8)
        put32(1024, into: &central, at: 20); put32(expanded, into: &central, at: 24)
        put16(UInt16(path.count), into: &central, at: 28); put32(mode << 16, into: &central, at: 38)
        central.append(path)
        var end = Data(repeating: 0, count: 22)
        put32(0x06054b50, into: &end, at: 0); put16(1, into: &end, at: 8); put16(1, into: &end, at: 10)
        put32(UInt32(central.count), into: &end, at: 12); put32(UInt32(local.count), into: &end, at: 16)
        return local + central + end
    }
    private func put16(_ value: UInt16, into data: inout Data, at offset: Int) { for i in 0..<2 { data[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) } }
    private func put32(_ value: UInt32, into data: inout Data, at offset: Int) { for i in 0..<4 { data[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) } }
}
