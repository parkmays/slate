import Foundation
import SLATESharedTypes

public enum AirtableRESTError: Error, Sendable {
    case invalidURL
    case http(Int, String?)
    case decoding(String)
}

/// Minimal Airtable Web API client (v0). One base per SLATE project — use `project.airtableBaseId` + `project.airtableAPIKey`.
public final class AirtableRESTClient: Sendable {
    private let apiKey: String
    private let baseId: String
    private let session: URLSession

    public init(apiKey: String, baseId: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseId = baseId
        self.session = session
    }

    /// Lists records in a table (paginates with `offset` from prior response).
    public func listRecords(
        tableName: String,
        pageSize: Int = 100,
        offset: String? = nil
    ) async throws -> AirtableListRecordsResponse {
        var components = URLComponents(string: "https://api.airtable.com/v0/\(baseId)/\(tableName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tableName)")
        var items: [URLQueryItem] = [URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let offset {
            items.append(URLQueryItem(name: "offset", value: offset))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw AirtableRESTError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AirtableRESTError.http(-1, nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AirtableRESTError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(AirtableListRecordsResponse.self, from: data)
        } catch {
            throw AirtableRESTError.decoding(error.localizedDescription)
        }
    }

    /// Creates or updates fields on a record. Caller supplies Airtable field names (see `AirtableProductionFieldMapping`).
    public func patchRecord(
        tableName: String,
        recordId: String,
        fields: [String: String]
    ) async throws {
        let encodedTable = tableName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tableName
        let encodedId = recordId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? recordId
        guard let url = URL(string: "https://api.airtable.com/v0/\(baseId)/\(encodedTable)/\(encodedId)") else {
            throw AirtableRESTError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONSerialization.data(withJSONObject: ["fields": fields], options: [])
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AirtableRESTError.http(-1, nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw AirtableRESTError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
    }

    /// Pushes **technical** read-only-on-Airtable fields from SLATE (duration, timecode, filename — mapped by field names).
    public func pushTechnicalFields(
        tableName: String,
        recordId: String,
        mapping: AirtableProductionFieldMapping,
        clip: Clip
    ) async throws {
        var fields: [String: String] = [:]
        fields[mapping.durationSeconds] = String(clip.duration)
        fields[mapping.sourceTimecode] = clip.sourceTimecodeStart
        fields[mapping.sourceFileName] = URL(fileURLWithPath: clip.sourcePath).lastPathComponent
        try await patchRecord(tableName: tableName, recordId: recordId, fields: fields)
    }
}

// MARK: - DTOs

public struct AirtableListRecordsResponse: Decodable, Sendable {
    public let records: [AirtableRecordDTO]
    public let offset: String?
}

public struct AirtableRecordDTO: Decodable, Sendable {
    public let id: String
    public let createdTime: String
    public let fields: [String: AirtableJSONValue]
}

/// Lossy JSON value decode for Airtable `fields` (strings, numbers, arrays).
public enum AirtableJSONValue: Decodable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AirtableJSONValue])
    case object([String: AirtableJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let strs = try? c.decode([String].self) {
            self = .array(strs.map { .string($0) })
        } else if let a = try? c.decode([AirtableJSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: AirtableJSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}

/// Field names in the per-show Airtable base — adjust to match the TD's template.
public struct AirtableProductionFieldMapping: Sendable, Equatable {
    public var slateClipId: String
    public var reviewStatus: String
    public var directorNotes: String
    public var lastModified: String
    public var durationSeconds: String
    public var sourceTimecode: String
    public var sourceFileName: String
    public var cameraRoll: String
    public var soundRoll: String

    public init(
        slateClipId: String = "SLATE Clip ID",
        reviewStatus: String = "Review Status",
        directorNotes: String = "Director Notes",
        lastModified: String = "Last Modified",
        durationSeconds: String = "Duration (sec)",
        sourceTimecode: String = "Source TC",
        sourceFileName: String = "Source File",
        cameraRoll: String = "Camera Roll",
        soundRoll: String = "Sound Roll"
    ) {
        self.slateClipId = slateClipId
        self.reviewStatus = reviewStatus
        self.directorNotes = directorNotes
        self.lastModified = lastModified
        self.durationSeconds = durationSeconds
        self.sourceTimecode = sourceTimecode
        self.sourceFileName = sourceFileName
        self.cameraRoll = cameraRoll
        self.soundRoll = soundRoll
    }
}
