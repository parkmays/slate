import Foundation
import SLATESharedTypes

/// Last-write-wins for **editorial** fields when comparing SLATE timestamps to an external system's modification time.
/// Technical metadata is **not** merged here — callers should only push those from SLATE to Airtable (SLATE is source of truth).
public enum EditorialMergePolicy: Sendable {

    /// - Parameters:
    ///   - slateEditorialModified: `clip.editorialUpdatedAt` parsed; when nil, `slateDocumentUpdated` is used as a fallback.
    ///   - slateDocumentUpdated: Typically `clip.updatedAt` — used only when editorial timestamp is absent.
    ///   - externalModified: Airtable row last-modified (e.g. Last modified time field) or ShotGrid `updated_at`.
    /// - Returns: `true` if the external copy should overwrite editorial fields in SLATE; `false` to keep SLATE's editorial state.
    public static func shouldApplyRemoteEditorial(
        slateEditorialModified: Date?,
        slateDocumentUpdated: Date,
        externalModified: Date?
    ) -> Bool {
        guard let externalModified else {
            return false
        }
        let slateAnchor = slateEditorialModified ?? slateDocumentUpdated
        return externalModified > slateAnchor
    }

    /// Parses ISO8601 strings from SLATE clip fields.
    public static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return Self.isoFormatter.date(from: raw) ?? Self.isoFractional.date(from: raw)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
