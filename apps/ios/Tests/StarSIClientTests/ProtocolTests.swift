import XCTest
@testable import StarSIClient

final class ProtocolTests: XCTestCase {
    func testStreamEventDecodesSnakeCase() throws {
        let json = #"{"type":"done","served_by":"macbook","model":"qwen3.8-27b"}"#
        let ev = try JSONDecoder.starsi.decode(StreamEvent.self, from: Data(json.utf8))
        XCTAssertEqual(ev.type, .done)
        XCTAssertEqual(ev.servedBy, "macbook")
    }
}
