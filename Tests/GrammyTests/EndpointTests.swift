import XCTest
@testable import Grammy

final class EndpointTests: XCTestCase {
    func testServerURLsResolveChatAndModels() throws {
        for base in ["http://localhost:1234", "http://127.0.0.1:1234", "http://[::1]:1234", "http://192.168.40.125:1234"] {
            for suffix in ["", "/", "/v1", "/v1/", "/v1/chat/completions"] {
                let endpoint = try LiteLLMClient.chatURL(from: " \n" + base + suffix + "\n")
                XCTAssertEqual(endpoint.absoluteString, base + "/v1/chat/completions")
                XCTAssertEqual(LiteLLMClient.modelsURL(for: endpoint).absoluteString, base + "/v1/models")
            }
        }
    }

    func testExistingEndpointsArePreserved() throws {
        for input in ["https://api.openai.com/v1/chat/completions", "https://example.com/proxy/chat/completions?api-version=1"] {
            XCTAssertEqual(try LiteLLMClient.chatURL(from: input).absoluteString, input)
        }
    }

    func testInvalidURLsAreRejected() {
        for input in ["", "localhost:1234", "file:///tmp/test", "https:///", "http://user:password@localhost:1234"] {
            XCTAssertThrowsError(try LiteLLMClient.chatURL(from: input))
        }
    }
}
