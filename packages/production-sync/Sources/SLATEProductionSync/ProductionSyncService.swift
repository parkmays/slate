import Foundation
import SLATESharedTypes

/// High-level helpers for Production Sync (orchestration hooks for UI / background tasks).
public enum ProductionSyncService: Sendable {

    /// Builds an Airtable client when the project has credentials configured.
    public static func makeAirtableClient(for project: Project) -> AirtableRESTClient? {
        guard let key = project.airtableAPIKey, !key.isEmpty,
              let base = project.airtableBaseId, !base.isEmpty
        else {
            return nil
        }
        return AirtableRESTClient(apiKey: key, baseId: base)
    }

    /// Builds a ShotGrid client when site + script credentials exist.
    public static func makeShotGridClient(for project: Project) -> ShotGridRESTClient? {
        guard let site = project.shotgridSite, !site.isEmpty,
              let name = project.shotgridScriptName, !name.isEmpty,
              let key = project.shotgridApplicationKey, !key.isEmpty
        else {
            return nil
        }
        return ShotGridRESTClient(siteSubdomain: site, scriptName: name, applicationKey: key)
    }

    /// Editorial merge decision for a clip vs an external modification timestamp.
    public static func shouldApplyRemoteEditorial(clip: Clip, externalModified: Date?) -> Bool {
        let editorial = EditorialMergePolicy.parseISODate(clip.editorialUpdatedAt)
        let doc = EditorialMergePolicy.parseISODate(clip.updatedAt) ?? Date.distantPast
        return EditorialMergePolicy.shouldApplyRemoteEditorial(
            slateEditorialModified: editorial,
            slateDocumentUpdated: doc,
            externalModified: externalModified
        )
    }
}
