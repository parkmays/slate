import Foundation
import XCTest
@testable import SLATECore

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ShareLinkServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testGenerateShareLinkUsesSupabaseHeadersAndSnakeCaseBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/functions/v1/generate-share-link")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Client-Info"), "slate-desktop")

            let bodyData = try XCTUnwrap(Self.requestBody(for: request))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(payload["project_id"] as? String, "project-123")
            XCTAssertEqual(payload["scope"] as? String, "project")
            XCTAssertEqual(payload["expiry_hours"] as? Int, 72)

            let permissions = try XCTUnwrap(payload["permissions"] as? [String: Any])
            XCTAssertEqual(permissions["can_comment"] as? Bool, true)
            XCTAssertEqual(permissions["can_flag"] as? Bool, false)
            XCTAssertEqual(permissions["can_request_alternate"] as? Bool, true)

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data(
                #"{"token":"share-token","url":"https://slate.app/review/share-token","expiresAt":"2026-04-01T00:00:00Z"}"#.utf8
            )
            return (response, data)
        }

        let result = try await makeService().generateShareLink(
            projectId: "project-123",
            scope: .project,
            expiryHours: 72,
            permissions: .init(canComment: true, canFlag: false, canRequestAlternate: true),
            jwt: "test-jwt"
        )

        XCTAssertEqual(result.token, "share-token")
        XCTAssertEqual(result.url, "https://slate.app/review/share-token")
    }

    func testSignProxyURLUsesShareTokenHeaderAndAnonKey() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/functions/v1/sign-proxy-url")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Share-Token"), "share-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

            let bodyData = try XCTUnwrap(Self.requestBody(for: request))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(payload["clip_id"] as? String, "clip-123")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data(
                #"{"signedUrl":"https://cdn.example/proxy.mp4","thumbnailUrl":"https://cdn.example/thumb.jpg","expiresAt":"2026-04-01T00:00:00Z"}"#.utf8
            )
            return (response, data)
        }

        let result = try await makeService().signProxyURL(
            clipId: "clip-123",
            auth: .shareToken("share-token")
        )

        XCTAssertEqual(result.signedUrl, "https://cdn.example/proxy.mp4")
        XCTAssertEqual(result.thumbnailUrl, "https://cdn.example/thumb.jpg")
    }

    func testGenerateShareLinkFailsFastWhenAnonKeyMissing() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = ShareLinkService(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "",
            session: session
        )

        do {
            _ = try await service.generateShareLink(
                projectId: "project-123",
                scope: .project,
                jwt: "test-jwt"
            )
            XCTFail("Expected notConfigured error")
        } catch let error as ShareLinkError {
            XCTAssertEqual(error.errorDescription, ShareLinkError.notConfigured.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeService() -> ShareLinkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return ShareLinkService(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "anon-key",
            session: session
        )
    }

    private static func requestBody(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }

        return data
    }
}
