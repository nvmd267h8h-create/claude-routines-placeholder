import Testing

@testable import ReEditCore

@Suite("Scaffold")
struct ScaffoldTests {
    @Test func versionIsPhase0() {
        #expect(ReEditCoreInfo.version.hasSuffix("-phase0"))
    }
}
