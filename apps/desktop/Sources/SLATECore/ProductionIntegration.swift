import Foundation
import SLATEProductionSync
import SLATESharedTypes

extension Project {
    /// Configured Airtable REST client for this project’s base, or nil if credentials are missing.
    public var airtableSyncClient: AirtableRESTClient? {
        ProductionSyncService.makeAirtableClient(for: self)
    }

    /// ShotGrid REST client (script credentials), or nil if not configured.
    public var shotGridSyncClient: ShotGridRESTClient? {
        ProductionSyncService.makeShotGridClient(for: self)
    }
}

extension Clip {
    /// Whether an Airtable row’s last-modified time should replace SLATE editorial fields (last-write-wins).
    public func shouldApplyRemoteEditorial(externalModified: Date?) -> Bool {
        ProductionSyncService.shouldApplyRemoteEditorial(clip: self, externalModified: externalModified)
    }
}
