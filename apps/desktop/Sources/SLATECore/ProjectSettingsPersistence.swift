// SLATE — Project delivery / digest settings (UserDefaults overlay)
// GRDB `projects` rows only store core identity; notification + digest fields persist here.

import Foundation
import SLATESharedTypes
import os.log

public enum ProjectSettingsPersistence {
    private static let defaultsKey = "SLATE.projectDeliverySettings.v1"
    private static let logger = Logger(subsystem: "com.mountaintop.slate", category: "ProjectSettingsPersistence")

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
              !data.isEmpty else {
            logger.debug("No persisted settings found for project \(project.id)")
            return project
        }
        
        do {
            let all = try JSONDecoder().decode([String: Persisted].self, from: data)
            guard let p = all[project.id] else {
                logger.debug("No settings found for project \(project.id)")
                return project
            }

            let mergedProject = Project(
                id: project.id,
                name: project.name,
                mode: project.mode,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt,
                notificationTargets: p.notificationTargets,
                autoDeliverOnAssembly: p.autoDeliverOnAssembly,
                digestTargets: p.digestTargets,
                digestHour: min(23, max(0, p.digestHour)),
                dailyDigestEnabled: p.dailyDigestEnabled,
                airtableAPIKey: project.airtableAPIKey,
                airtableBaseId: project.airtableBaseId,
                shotgridScriptName: project.shotgridScriptName,
                shotgridApplicationKey: project.shotgridApplicationKey,
                shotgridSite: project.shotgridSite
            )
            
            logger.info("Successfully merged persisted settings for project \(project.id)")
            return mergedProject
            
        } catch {
            logger.error("Failed to decode persisted settings: \(error.localizedDescription)")
            // Return original project if decode fails
            return project
        }
    }

    public static func save(_ project: Project) {
        var all: [String: Persisted] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           !data.isEmpty {
            do {
                all = try JSONDecoder().decode([String: Persisted].self, from: data)
            } catch {
                logger.error("Failed to decode existing settings while saving: \(error.localizedDescription)")
                // Continue with empty dictionary - better than losing new settings
            }
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

        do {
            let data = try JSONEncoder().encode(all)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            logger.info("Successfully saved settings for project \(project.id)")
        } catch {
            logger.error("Failed to encode project settings: \(error.localizedDescription)")
            // In production, you might want to show an alert to the user
        }
    }

    public static func loadTranscodeProfiles(projectId: String) -> (profiles: [ProxyTranscodeProfile], selectedProfileId: String?) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              !data.isEmpty else {
            logger.debug("No transcode profiles found for project \(projectId)")
            return ([.slateDefault], nil)
        }
        
        do {
            let all = try JSONDecoder().decode([String: Persisted].self, from: data)
            guard let project = all[projectId] else {
                logger.debug("No transcode profiles for project \(projectId)")
                return ([.slateDefault], nil)
            }
            let profiles = (project.transcodeProfiles?.isEmpty == false) ? (project.transcodeProfiles ?? [.slateDefault]) : [.slateDefault]
            logger.debug("Loaded \(profiles.count) transcode profiles for project \(projectId)")
            return (profiles, project.selectedTranscodeProfileId)
            
        } catch {
            logger.error("Failed to decode transcode profiles: \(error.localizedDescription)")
            return ([.slateDefault], nil)
        }
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
        do {
            let encoded = try JSONEncoder().encode(all)
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
            logger.info("Successfully saved \(profiles.count) transcode profiles for project \(projectId)")
        } catch {
            logger.error("Failed to encode transcode profiles: \(error.localizedDescription)")
        }
    }
}
