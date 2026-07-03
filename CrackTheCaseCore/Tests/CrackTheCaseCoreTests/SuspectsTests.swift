import Testing
@testable import CrackTheCaseCore

@Suite("Suspects roster")
struct SuspectsTests {
    @Test("there are exactly 6 suspects")
    func sixSuspects() {
        #expect(Suspects.all.count == 6)
    }

    @Test("every suspect has a unique id")
    func uniqueIDs() {
        let ids = Suspects.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
