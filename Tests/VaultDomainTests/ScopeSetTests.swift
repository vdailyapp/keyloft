import Foundation
import Testing

@testable import VaultDomain

@Suite("ScopeSet")
struct ScopeSetTests {
    @Test("U1: chuỗi rỗng / chỉ khoảng trắng → empty")
    func emptyInput() {
        #expect(ScopeSet(spaceDelimited: "").isEmpty)
        #expect(ScopeSet(spaceDelimited: "   \t \n ").isEmpty)
        #expect(ScopeSet(spaceDelimited: "").spaceDelimited == "")
    }

    @Test("U2: tách nhiều loại whitespace, bỏ trùng")
    func whitespaceSplitDedup() {
        let set = ScopeSet(spaceDelimited: " openid\temail  email\n")
        #expect(set.values == ["openid", "email"])
    }

    @Test("U3: phân biệt hoa thường")
    func caseSensitive() {
        let set: ScopeSet = ["Files.Read", "files.read"]
        #expect(set.count == 2)
    }

    @Test("U4: spaceDelimited ổn định, đã sort")
    func stableOutput() {
        let set: ScopeSet = ["b", "a", "c"]
        #expect(set.spaceDelimited == "a b c")
    }

    @Test("U5: missing(in:) trả scope cần mà chưa được cấp")
    func missing() {
        let requested: ScopeSet = ["drive", "openid", "email"]
        let granted: ScopeSet = ["openid", "email"]
        #expect(requested.missing(in: granted) == ["drive"])
        #expect(requested.missing(in: requested).isEmpty)
    }

    @Test("U6: Codable encode mảng đã sort, round-trip bằng nhau")
    func codable() throws {
        let set: ScopeSet = ["b", "a"]
        let data = try JSONEncoder().encode(set)
        // Encode thành mảng đã sort: ["a","b"]
        #expect(try JSONDecoder().decode([String].self, from: data) == ["a", "b"])
        #expect(try JSONDecoder().decode(ScopeSet.self, from: data) == set)
    }

    @Test("Scope Unicode giữ nguyên, không normalize")
    func unicodeUntouched() {
        let set = ScopeSet(["ộ.drive"])
        #expect(set.contains("ộ.drive"))
    }
}
