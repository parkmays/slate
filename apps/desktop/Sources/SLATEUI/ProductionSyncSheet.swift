import SLATECore
import SLATESharedTypes
import SwiftUI

/// Per-project Airtable / ShotGrid credentials (stored in local GRDB).
public struct ProductionSyncSheet: View {
    private let project: Project
    private let projectStore: ProjectStore
    private let clipStore: GRDBClipStore

    @Environment(\.dismiss) private var dismiss
    @State private var airtableKey: String
    @State private var airtableBase: String
    @State private var shotgridSite: String
    @State private var shotgridScript: String
    @State private var shotgridKey: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    public init(project: Project, projectStore: ProjectStore, clipStore: GRDBClipStore) {
        self.project = project
        self.projectStore = projectStore
        self.clipStore = clipStore
        _airtableKey = State(initialValue: project.airtableAPIKey ?? "")
        _airtableBase = State(initialValue: project.airtableBaseId ?? "")
        _shotgridSite = State(initialValue: project.shotgridSite ?? "")
        _shotgridScript = State(initialValue: project.shotgridScriptName ?? "")
        _shotgridKey = State(initialValue: project.shotgridApplicationKey ?? "")
    }

    public var body: some View {
        Form {
            Section("Airtable (one base per project)") {
                SecureField("API key (PAT)", text: $airtableKey)
                TextField("Base ID (app…)", text: $airtableBase)
            }
            Section("ShotGrid (script credentials)") {
                TextField("Site subdomain (e.g. myshow)", text: $shotgridSite)
                TextField("Script name", text: $shotgridScript)
                SecureField("Application key", text: $shotgridKey)
            }
            if let errorMessage {
                Text(errorMessage).foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving)
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var p = project
        p.airtableAPIKey = airtableKey.isEmpty ? nil : airtableKey
        p.airtableBaseId = airtableBase.isEmpty ? nil : airtableBase
        p.shotgridSite = shotgridSite.isEmpty ? nil : shotgridSite
        p.shotgridScriptName = shotgridScript.isEmpty ? nil : shotgridScript
        p.shotgridApplicationKey = shotgridKey.isEmpty ? nil : shotgridKey
        p.updatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            try await projectStore.persistProjectProductionIntegrations(p, clipStore: clipStore)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
