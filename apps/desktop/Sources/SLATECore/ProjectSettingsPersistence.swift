// SLATE — Project delivery / digest settings (UserDefaults overlay)
// GRDB `projects` rows only store core identity; notification + digest fields persist here.

import Foundation
import SLATESharedTypes

public enum ProjectSettingsPersistence {
    private static let defaultsKey = "SLATE.projectDeliverySettings.v1"

    private struct Persisted: Codable, Sendable {
        var notificationTargets: [DeliveryTarget]
        var autoDeliverOnAssembly: Bool
        var digestTargets: [DeliveryTarget]
        var digestHour: Int
        var dailyDigestEnabled: Bool
        var transcodeProfiles: [ProxyTranscodeProfile]?
        var selectedTranscodeProfileId: String?
    }

    public static func merge(into project: Project) -> Project {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              !data.isEmpty,
              let all = try? JSONDecoder().decode([String: Persisted].self, from: data),
              let p = all[project.id] else {
            return project
        }

        return Project(
            id: project.id,
            name: project.name,
            mode: project.mode,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            notificationTargets: p.notificationTargets,
            autoDeliverOnAssembly: p.autoDeliverOnAssembly,
            digestTargets: p.digestTargets,
            digestHour: min(23, max(0, p.digestHour)),
            dailyDigestEnabled: p.dailyDigestEnabled
        )
    }

    public static func save(_ project: Project) {
        var all: [String: Persisted] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           !data.isEmpty,
           let decoded = try? JSONDecoder().decode([String: Persisted].self, from: data) {
            all = decoded
        }

        all[project.id] = Persisted(
            notificationTargets: project.notificationTargets,
            autoDeliverOnAssembly: project.autoDeliverOnAssembly,
            digestTargets: project.digestTargets,
            digestHour: min(23, max(0, project.digestHour)),
            dailyDigestEnabled: project.dailyDigestEnabled,
            transcodeProfiles: all[project.id]?.transcodeProfiles,
            selectedTranscodeProfileId: all[project.id]?.selectedTranscodeProfileId
        )

        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    public static func loadTranscodeProfiles(projectId: String) -> (profiles: [ProxyTranscodeProfile], selectedProfileId: String?) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              !data.isEmpty,
              let all = try? JSONDecoder().decode([String: Persisted].self, from: data),
              let project = all[projectId]
        else {
            return ([.slateDefault], nil)
        }
        let profiles = (project.transcodeProfiles?.isEmpty == false) ? (project.transcodeProfiles ?? [.slateDefault]) : [.slateDefault]
        return (profiles, project.selectedTranscodeProfileId)
    }

    public static func saveTranscodeProfiles(projectId: String, profiles: [ProxyTranscodeProfile], selectedProfileId: String?) {
        var all: [String: Persisted] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           !data.isEmpty,
           let decoded = try? JSONDecoder().decode([String: Persisted].self, from: data) {
            all = decoded
        }
        let existing = all[projectId] ?? Persisted(
            notificationTargets: [],
            autoDeliverOnAssembly: false,
            digestTargets: [],
            digestHour: 21,
            dailyDigestEnabled: false,
            transcodeProfiles: nil,
            selectedTranscodeProfileId: nil
        )
        all[projectId] = Persisted(
            notificationTargets: existing.notificationTargets,
            autoDeliverOnAssembly: existing.autoDeliverOnAssembly,
            digestTargets: existing.digestTargets,
            digestHour: existing.digestHour,
            dailyDigestEnabled: existing.dailyDigestEnabled,
            transcodeProfiles: profiles,
            selectedTranscodeProfileId: selectedProfileId
        )
        if let encoded = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
}
