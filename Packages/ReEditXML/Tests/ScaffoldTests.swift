import Testing

@testable import ReEditXML

@Suite("Scaffold")
struct ScaffoldTests {
    @Test func versionMatchesCore() {
        #expect(ReEditXMLInfo.version.hasSuffix("-phase0"))
    }
}
