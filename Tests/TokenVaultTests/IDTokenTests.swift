import Foundation
import KeyloftTestSupport
import Testing
import TokenVault
import VaultDomain

@Suite("IDToken")
struct IDTokenTests {
    static let now = Date(timeIntervalSince1970: 1_761_353_600)

    @Test("U27: aud dạng string và array đều decode thành mảng")
    func audFormats() throws {
        let arrayForm = TestJWT.make(
            claims: TestJWT.claims(iss: "https://accounts.google.com", aud: ["a", "b"]))
        let stringForm = TestJWT.make(
            claims: TestJWT.claims(iss: "https://accounts.google.com").replacingOccurrences(
                of: "\"aud\": [\"client-1\"]", with: "\"aud\": \"client-1\""))

        let fromArray = try IDTokenClaims.decode(arrayForm)
        let fromString = try IDTokenClaims.decode(stringForm)
        #expect(fromArray.aud == ["a", "b"])
        #expect(fromString.aud == ["client-1"])
    }

    @Test("U28: JWT hỏng — 2 phần, base64 sai, alg none")
    func brokenJWT() throws {
        #expect(throws: OAuthError.invalidIDToken("JWT phải có đúng 3 phần")) {
            _ = try IDTokenClaims.decode("two.parts")
        }
        let badBase64 = "x.###.y"
        #expect(throws: OAuthError.self) { _ = try IDTokenClaims.decode(badBase64) }

        let algNone = TestJWT.make(header: #"{"alg":"none"}"#, claims: TestJWT.claims(iss: "x"))
        #expect(throws: OAuthError.invalidIDToken("alg none không được chấp nhận")) {
            _ = try IDTokenClaims.decode(algNone)
        }
    }

    @Test("U29: aud không chứa clientId → throw")
    func audMismatch() throws {
        let jwt = TestJWT.make(
            claims: TestJWT.claims(iss: "https://accounts.google.com", aud: ["other-app"]))
        let claims = try IDTokenClaims.decode(jwt)
        #expect(throws: OAuthError.self) {
            try claims.validate(provider: TestData.googleProvider, clientId: "client-1", now: Self.now)
        }
    }

    @Test("U30: exp quá hạn ngoài leeway throw; trong leeway thì qua")
    func expiryLeeway() throws {
        let expDate = Self.now.addingTimeInterval(-301)
        let expired = try IDTokenClaims.decode(
            TestJWT.make(claims: TestJWT.claims(iss: "https://accounts.google.com", exp: expDate.timeIntervalSince1970))
        )
        #expect(throws: OAuthError.self) {
            try expired.validate(provider: TestData.googleProvider, clientId: "client-1", now: Self.now)
        }

        let almost = try IDTokenClaims.decode(
            TestJWT.make(
                claims: TestJWT.claims(
                    iss: "https://accounts.google.com", exp: Self.now.addingTimeInterval(-299).timeIntervalSince1970)))
        try almost.validate(provider: TestData.googleProvider, clientId: "client-1", now: Self.now)
    }

    @Test("U31: Google iss sai → throw")
    func wrongIssuer() throws {
        let jwt = TestJWT.make(claims: TestJWT.claims(iss: "https://evil.example"))
        let claims = try IDTokenClaims.decode(jwt)
        #expect(
            throws: OAuthError.issuerMismatch(expected: "https://accounts.google.com", actual: "https://evil.example")
        ) {
            try claims.validate(provider: TestData.googleProvider, clientId: "client-1", now: Self.now)
        }
    }

    @Test("U32: Microsoft issuer template theo tid")
    func microsoftTemplate() throws {
        let provider = TestData.microsoftProvider
        let good = try IDTokenClaims.decode(
            TestJWT.make(
                claims: TestJWT.claims(
                    iss: "https://login.microsoftonline.com/TENANT-9/v2.0", tid: "TENANT-9")))
        try good.validate(provider: provider, clientId: "client-1", now: Self.now)

        let wrongTenant = try IDTokenClaims.decode(
            TestJWT.make(
                claims: TestJWT.claims(
                    iss: "https://login.microsoftonline.com/OTHER/v2.0", tid: "TENANT-9")))
        #expect(
            throws: OAuthError.issuerMismatch(
                expected: "https://login.microsoftonline.com/TENANT-9/v2.0",
                actual: "https://login.microsoftonline.com/OTHER/v2.0")
        ) {
            try wrongTenant.validate(provider: provider, clientId: "client-1", now: Self.now)
        }

        let missingTid = try IDTokenClaims.decode(
            TestJWT.make(
                claims: TestJWT.claims(iss: "https://login.microsoftonline.com/TENANT-9/v2.0")))
        #expect(throws: OAuthError.invalidIDToken("issuer dạng template nhưng thiếu tid")) {
            try missingTid.validate(provider: provider, clientId: "client-1", now: Self.now)
        }
    }

    @Test("bestEmail: email thắng, fallback preferred_username")
    func bestEmail() throws {
        let withEmail = try IDTokenClaims.decode(
            TestJWT.make(claims: TestJWT.claims(iss: "https://accounts.google.com")))
        #expect(withEmail.bestEmail == "user@example.test")
    }
}
