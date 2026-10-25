import Foundation
import KeyloftTestSupport
import Testing
import TokenVault

@Suite("PKCE")
struct PKCETests {
    @Test("U1: vector RFC 7636 Appendix B")
    func rfcVector() throws {
        let pair = try PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pair.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(pair.method == "S256")
    }

    @Test("U2: verifier sai độ dài / ký tự → throw")
    func invalidVerifiers() throws {
        #expect(throws: OAuthCryptoError.self) {
            _ = try PKCEPair(verifier: String(repeating: "a", count: 42))
        }
        #expect(throws: OAuthCryptoError.self) {
            _ = try PKCEPair(verifier: String(repeating: "a", count: 129))
        }
        #expect(throws: OAuthCryptoError.self) {
            _ = try PKCEPair(verifier: "abc+def/\(String(repeating: "a", count: 40))")
        }
    }

    @Test("U3: generate từ SeededRandomSource — 43 ký tự unreserved, 2 seed khác nhau")
    func generate() throws {
        let pair = try PKCEPair.generate(using: SeededRandomSource(seed: 1))
        #expect(pair.verifier.count == 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pair.verifier.unicodeScalars.allSatisfy({ allowed.contains($0) }))

        let other = try PKCEPair.generate(using: SeededRandomSource(seed: 2))
        #expect(pair.verifier != other.verifier)
        #expect(pair != other)

        // Generate dùng đúng đường generate: verifier khớp init(verifier:)
        let roundTrip = try PKCEPair(verifier: pair.verifier)
        #expect(roundTrip.challenge == pair.challenge)
    }

    @Test("U4: state 43 ký tự base64url, không padding")
    func state() throws {
        let state = try OAuthState.generate(using: SeededRandomSource(seed: 9))
        #expect(state.count == 43)
        #expect(!state.contains("="))
        #expect(!state.contains("+"))
        #expect(!state.contains("/"))
        #expect(Base64URL.decode(state) != nil)
    }

    @Test("U5: constantTimeEquals")
    func constantTime() {
        #expect(constantTimeEquals("abc", "abc"))
        #expect(!constantTimeEquals("abc", "abd"))
        #expect(!constantTimeEquals("abc", "ab"))
        #expect(!constantTimeEquals("", "a"))
        #expect(constantTimeEquals("", ""))
    }
}
