import Foundation
import Testing
import SLATEProductionSync

@Suite("Editorial merge (last-write-wins)")
struct EditorialMergePolicyTests {

    @Test("Prefers SLATE when external time is older")
    func slateNewer() {
        let slate = Date(timeIntervalSince1970: 2_000_000)
        let external = Date(timeIntervalSince1970: 1_000_000)
        let apply = EditorialMergePolicy.shouldApplyRemoteEditorial(
            slateEditorialModified: slate,
            slateDocumentUpdated: slate,
            externalModified: external
        )
        #expect(apply == false)
    }

    @Test("Applies remote when external is newer than SLATE editorial")
    func remoteNewer() {
        let slate = Date(timeIntervalSince1970: 1_000_000)
        let external = Date(timeIntervalSince1970: 2_000_000)
        let apply = EditorialMergePolicy.shouldApplyRemoteEditorial(
            slateEditorialModified: slate,
            slateDocumentUpdated: slate,
            externalModified: external
        )
        #expect(apply == true)
    }

    @Test("Nil external never overwrites")
    func nilExternal() {
        let slate = Date(timeIntervalSince1970: 1_000_000)
        let apply = EditorialMergePolicy.shouldApplyRemoteEditorial(
            slateEditorialModified: slate,
            slateDocumentUpdated: slate,
            externalModified: nil
        )
        #expect(apply == false)
    }

    @Test("Falls back to document updated when editorial timestamp missing")
    func fallbackDocument() {
        let doc = Date(timeIntervalSince1970: 3_000_000)
        let external = Date(timeIntervalSince1970: 4_000_000)
        let apply = EditorialMergePolicy.shouldApplyRemoteEditorial(
            slateEditorialModified: nil,
            slateDocumentUpdated: doc,
            externalModified: external
        )
        #expect(apply == true)
    }
}
