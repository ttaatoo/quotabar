import XCTest
@testable import QuotaBar

final class HTTPClassifyTests: XCTestCase {
    func testCloudflareHTML403IsCheckpointNotUnauthorized() {
        let html = Data(
            """
            <!DOCTYPE html><html><body>Attention Required! Cloudflare</body></html>
            """.utf8
        )
        XCTAssertEqual(
            HTTPClassify.classify(status: 403, data: html, contentType: "text/html"),
            .checkpoint
        )
        XCTAssertFalse(HTTPClassify.isUnauthenticated(status: 403, data: html, contentType: "text/html"))
    }

    func testJSON403WithoutAuthMarkersIsFailure() throws {
        let body = Data(#"{"error":"forbidden","message":"plan required"}"#.utf8)
        XCTAssertEqual(
            HTTPClassify.classify(status: 403, data: body, contentType: "application/json"),
            .failure
        )
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        XCTAssertThrowsError(try HTTPClassify.requireOK(response, data: body, host: "example.com")) { error in
            guard let quota = error as? QuotaError else {
                return XCTFail("expected QuotaError")
            }
            XCTAssertFalse(quota.isAuthFailure)
            if case .http(let code, _) = quota {
                XCTAssertEqual(code, 403)
            } else {
                XCTFail("expected http 403, got \(quota)")
            }
        }
    }

    func testJSON401AndUnauthenticatedJSONAreUnauthorized() {
        let body = Data(#"{"error":"not_authenticated"}"#.utf8)
        XCTAssertEqual(
            HTTPClassify.classify(status: 401, data: body, contentType: "application/json"),
            .unauthorized
        )
        XCTAssertEqual(
            HTTPClassify.classify(status: 403, data: Data(#"{"code":"unauthenticated"}"#.utf8), contentType: "application/json"),
            .unauthorized
        )
        XCTAssertEqual(
            HTTPClassify.classify(
                status: 403,
                data: Data(#"{"code":"token_expired"}"#.utf8),
                contentType: "application/json"
            ),
            .unauthorized
        )
    }

    func testPermission403IsNotAuthAndJSONCloudflareIsNotCheckpoint() {
        let sku = Data(#"{"error":"forbidden","message":"user unauthorized for this SKU"}"#.utf8)
        XCTAssertEqual(
            HTTPClassify.classify(status: 403, data: sku, contentType: "application/json"),
            .failure
        )
        let mentioned = Data(#"{"error":"forbidden","note":"cloudflare attention required"}"#.utf8)
        XCTAssertEqual(
            HTTPClassify.classify(status: 403, data: mentioned, contentType: "application/json"),
            .failure
        )
        XCTAssertEqual(
            HTTPClassify.classify(
                status: 200,
                data: Data(#"{"message":"unauthorized"}"#.utf8),
                contentType: "application/json"
            ),
            .ok
        )
    }

    func test429IsRateLimitedNotAuth() throws {
        XCTAssertEqual(
            HTTPClassify.classify(status: 429, data: Data("slow down".utf8), contentType: "text/plain"),
            .rateLimited
        )
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        ))
        XCTAssertThrowsError(try HTTPClassify.requireOK(response, data: Data(), host: "example.com")) { error in
            let quota = error as? QuotaError
            XCTAssertFalse(quota?.isAuthFailure ?? true)
            if case .http(let code, _) = quota {
                XCTAssertEqual(code, 429)
            } else {
                XCTFail("expected http 429")
            }
        }
    }

    func testCodexRefresh503IsNotLoginExpired() {
        let kind = HTTPClassify.classify(
            status: 503,
            data: Data("unavailable".utf8),
            contentType: "text/plain"
        )
        XCTAssertEqual(kind, .failure)
        XCTAssertFalse(kind == .unauthorized)
    }

    func testOpenCodeEntitlementJSONOnly() {
        let entitlement = Data(#"{"name":"EntitlementError"}"#.utf8)
        XCTAssertTrue(OpenCodeGoClient.isEntitlementDenial(data: entitlement))
        XCTAssertFalse(OpenCodeGoClient.isEntitlementDenial(data: Data("<html>denied</html>".utf8)))
        XCTAssertFalse(OpenCodeGoClient.isEntitlementDenial(data: Data(#"{"error":"forbidden"}"#.utf8)))
    }
}
