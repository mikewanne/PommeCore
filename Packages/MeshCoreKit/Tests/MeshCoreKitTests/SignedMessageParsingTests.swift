//
//  SignedMessageParsingTests.swift
//  MeshCoreKit
//
//  txt_type 2 (signed plain) messages, e.g. posts pushed by a room server,
//  carry a 4-byte author public-key prefix before the UTF-8 text.
//

import XCTest
@testable import MeshCoreKit

final class SignedMessageParsingTests: XCTestCase {
    private let timestamp: [UInt8] = [0x00, 0x2D, 0x31, 0x6A]  // little-endian uint32

    /// RESP_CODE_CONTACT_MSG_RECV_V3 (0x10):
    /// snr(1) reserved(2) pubkey_prefix(6) path_len(1) txt_type(1) timestamp(4) [author(4)] text
    private func v3Frame(txtType: UInt8, author: [UInt8], text: String) -> Data {
        var bytes: [UInt8] = [0x10, 0x28, 0x00, 0x00]
        bytes += [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        bytes += [0x00, txtType]
        bytes += timestamp
        bytes += author
        bytes += Array(text.utf8)
        return Data(bytes)
    }

    /// RESP_CODE_CONTACT_MSG_RECV (0x07):
    /// pubkey_prefix(6) path_len(1) txt_type(1) timestamp(4) [author(4)] text
    private func v1Frame(txtType: UInt8, author: [UInt8], text: String) -> Data {
        var bytes: [UInt8] = [0x07]
        bytes += [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        bytes += [0x00, txtType]
        bytes += timestamp
        bytes += author
        bytes += Array(text.utf8)
        return Data(bytes)
    }

    private func parsedMessage(_ frame: Data, file: StaticString = #filePath, line: UInt = #line) -> Message? {
        guard case .contactMsgRecv(let message) = FrameParser.parse(frame) else {
            XCTFail("expected contactMsgRecv", file: file, line: line)
            return nil
        }
        return message
    }

    /// Author prefix that is not valid UTF-8 (A4 80): previously the whole
    /// text decoded to nil and the room post was shown as an empty bubble.
    func testSignedV3MessageWithNonUTF8AuthorPrefixKeepsText() {
        let text = "[EVENT 29.09.] Sinfoniekonzert im Kulturzentrum Herne"
        let message = parsedMessage(v3Frame(txtType: 2, author: [0x0E, 0xA4, 0x80, 0x40], text: text))
        XCTAssertEqual(message?.text, text)
        XCTAssertEqual(message?.isSigned, true)
    }

    /// Author prefix that happens to be ASCII (1A 42 20 79): previously the
    /// bytes leaked into the text as "B y".
    func testSignedV3MessageWithASCIIAuthorPrefixDoesNotLeakIntoText() {
        let text = "[VERK 00:16] Heinestr. Herne: Vollsperrung ab 28.09."
        let message = parsedMessage(v3Frame(txtType: 2, author: [0x1A, 0x42, 0x20, 0x79], text: text))
        XCTAssertEqual(message?.text, text)
    }

    func testSignedV1MessageSkipsAuthorPrefix() {
        let text = "Room post"
        let message = parsedMessage(v1Frame(txtType: 2, author: [0x0E, 0xA4, 0x80, 0x40], text: text))
        XCTAssertEqual(message?.text, text)
    }

    func testPlainMessageTextIsUnchanged() {
        let text = "Hello mesh"
        XCTAssertEqual(parsedMessage(v3Frame(txtType: 0, author: [], text: text))?.text, text)
        XCTAssertEqual(parsedMessage(v1Frame(txtType: 0, author: [], text: text))?.text, text)
    }

    /// txt_type 1 (CLI data) has no author prefix and must stay untouched.
    func testCLIDataMessageTextIsUnchanged() {
        let text = "OK - clock set"
        XCTAssertEqual(parsedMessage(v3Frame(txtType: 1, author: [], text: text))?.text, text)
    }

    func testTruncatedSignedMessageDoesNotCrash() {
        let message = parsedMessage(v3Frame(txtType: 2, author: [0x0E, 0xA4], text: ""))
        XCTAssertEqual(message?.text, "")
    }
}
