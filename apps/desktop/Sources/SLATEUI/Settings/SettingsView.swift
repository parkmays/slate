// SLATE — SettingsView
// Owned by: Claude Code
//
// Extensible settings panel with sections for different app configurations.
// Uses SettingsSection protocol for easy addition of new settings categories.

import SwiftUI
import SLATECore
import SLATESharedTypes

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var appSettings = AppSettingsPersistence()
    
    @State private var selectedSection: SettingsSectionID? = .general
    @State private var showingResetAlert = false
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsSectionID.allCases, id: \.self, selection: $selectedSection) { sectionID in
                Label {
                    Text(sectionID.title)
                } icon: {
                    Image(systemName: sectionID.icon)
                        .frame(width: 20)
                }
                .tooltip(sectionID.description)
            }
            .navigationTitle("Settings")
            .frame(minWidth: 200)
        } detail: {
            // Detail view
            Group {
                if let sectionID = selectedSection {
                    sectionID.sectionView(appSettings: appSettings)
                } else {
                    Text("Select a section")
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 400, minHeight: 500)
            .navigationTitle(selectedSection?.title ?? "Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .tooltip("Close settings", shortcut: .escape)
                }
                
                ToolbarItem {
                    Button("Reset All") {
                        showingResetAlert = true
                    }
                    .tooltip("Reset all settings to defaults")
                }
            }
        }
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                appSettings.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
    }
}

// MARK: - Settings Section ID

enum SettingsSectionID: CaseIterable {
    case general
    case processing
    case interface
    case shortcuts
    case cloud
    case advanced
    
    var title: String {
        switch self {
        case .general: return "General"
        case .processing: return "Processing"
        case .interface: return "Interface"
        case .shortcuts: return "Shortcuts"
        case .cloud: return "Cloud & Sync"
        case .advanced: return "Advanced"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .processing: return "cpu"
        case .interface: return "paintbrush"
        case .shortcuts: return "keyboard"
        case .cloud: return "icloud"
        case .advanced: return "gearshape.2"
        }
    }
    
    var description: String {
        switch self {
        case .general: return "General app settings and preferences"
        case .processing: return "Media processing and performance options"
        case .interface: return "UI customization and appearance"
        case .shortcuts: return "Keyboard shortcuts and hotkeys"
        case .cloud: return "Cloud sync and integration settings"
        case .advanced: return "Advanced configuration options"
        }
    }
    
    @ViewBuilder
    func sectionView(appSettings: AppSettingsPersistence) -> some View {
        switch self {
        case .general:
            GeneralSettingsSection(appSettings: appSettings)
        case .processing:
            ProcessingSettingsSection(appSettings: appSettings)
        case .interface:
            InterfaceSettingsSection(appSettings: appSettings)
        case .shortcuts:
            ShortcutsSettingsSection(appSettings: appSettings)
        case .cloud:
            CloudSettingsSection(appSettings: appSettings)
        case .advanced:
            AdvancedSettingsSection(appSettings: appSettings)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsSection: View {
    @ObservedObject var appSettings: AppSettingsPersistence
    
    var body: some View {
        Form {
            Section {
                Picker("Default Project Mode", selection: $appSettings.defaultProjectMode) {
                    Text("Narrative").tag(ProjectMode.narrative)
                    Text("Documentary").tag(ProjectMode.documentary)
                }
                .tooltip("Set the default mode for new projects")
                
                Toggle("Auto-save projects", isOn: $appSettings.autoSaveEnabled)
                    .tooltip("Automatically save project changes")
                
                Stepper(value: $appSettings.autoSaveInterval, in: 30...300, step: 30) {
                    Text("Auto-save every \(appSettings.autoSaveInterval) seconds")
                        .tooltip("Interval between auto-saves")
                }
            } header: {
                Text("Project Settings")
            }
            
            Section {
                TextField("Default clip name format", text: $appSettings.clipNameFormat)
                    .tooltip("Template for new clip names (use {scene}, {take}, {camera})")
                
                Picker("Timecode format", selection: $appSettings.timecodeFormat) {
                    Text("Drop Frame").tag(TimecodeFormat.dropFrame)
                    Text("Non-Drop Frame").tag(TimecodeFormat.nonDropFrame)
                    Text("Seconds").tag(TimecodeFormat.seconds)
                }
                .tooltip("Default timecode display format")
            } header: {
                Text("Media Settings")
            }
        }
        .padding()
    }
}

// MARK: - Processing Settings

struct ProcessingSettingsSection: View {
    @ObservedObject var appSettings: AppSettingsPersistence
    
    var body: some View {
        Form {
            Section {
                Toggle("Generate proxies on ingest", isOn: $appSettings.generateProxies)
                    .tooltip("Create proxy files for faster playback")
                
                if appSettings.generateProxies {
                    Picker("Proxy resolution", selection: $appSettings.proxyResolution) {
                        Text("720p").tag(ProxyResolution.hd720)
                        Text("1080p").tag(ProxyResolution.hd1080)
                        Text("540p").tag(ProxyResolution.sd540)
                    }
                    .tooltip("Resolution for generated proxy files")
                    
                    Toggle("Burn-in timecode", isOn: $appSettings.proxyBurnInTimecode)
                        .tooltip("Overlay timecode on proxy files")
                }
            } header: {
                Text("Proxy Generation")
            }
            
            Section {
                Toggle("Enable AI scoring", isOn: $appSettings.aiScoringEnabled)
                    .tooltip("Analyze clips with AI for quality scoring")
                
                Toggle("Face detection", isOn: $appSettings.faceDetectionEnabled)
                    .tooltip("Detect and group faces in clips")
                
                Toggle("Speech transcription", isOn: $appSettings.transcriptionEnabled)
                    .tooltip("Generate transcripts for speech content")
            } header: {
                Text("AI Processing")
            }
            
            Section {
                Slider(value: $appSettings.maxConcurrentJobs, in: 1...8, step: 1) {
                    Text("Max concurrent jobs: \(Int(appSettings.maxConcurrentJobs))")
                        .tooltip("Number of processing jobs to run simultaneously")
                }
                
                Picker("Processing priority", selection: $appSettings.processingPriority) {
                    Text("Low").tag(ProcessingPriority.low)
                    Text("Normal").tag(ProcessingPriority.normal)
                    Text("High").tag(ProcessingPriority.high)
                }
                .tooltip("CPU priority for background processing")
            } header: {
                Text("Performance")
            }
        }
        .padding()
    }
}

// MARK: - Interface Settings

struct InterfaceSettingsSection: View {
    @ObservedObject var appSettings: AppSettingsPersistence
    
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appSettings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .tooltip("Choose the app appearance")
                
                Slider(value: $appSettings.uiScale, in: 0.5...2.0, step: 0.1) {
                    Text("UI Scale: \(Int(appSettings.uiScale * 100))%")
                        .tooltip("Adjust the size of UI elements")
                }
            } header: {
                Text("Appearance")
            }
            
            Section {
                Toggle("Show tooltips", isOn: $appSettings.showTooltips)
                    .tooltip("Display helpful tooltips on hover")
                
                Toggle("Show keyboard shortcuts", isOn: $appSettings.showShortcutsInTooltips)
                    .tooltip("Include keyboard shortcuts in tooltips")
                
                Toggle("Animate transitions", isOn: $appSettings.animationsEnabled)
                    .tooltip("Enable UI animations and transitions")
            } header: {
                Text("User Assistance")
            }
            
            Section {
                TextField("Custom toolbar items", text: $appSettings.customToolbarItems)
                    .tooltip("Comma-separated list of toolbar actions")
                
                Toggle("Show toolbar labels", isOn: $appSettings.showToolbarLabels)
                    .tooltip("Display text labels on toolbar buttons")
            } header: {
                Text("Toolbar")
            }
        }
        .padding()
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsSection: View {
    @ObservedObject var appSettings: AppSettingsPersistence
    
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Text(action.currentShortcut)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .tooltip(action.description)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Shortcut customization coming soon. Use the help menu to see all available shortcuts.")
            }
        }
        .padding()
    }
}

// MARK: - Cloud Settings

struct CloudSettingsSection: View {
    @ObservedObject var appSettings: AppSettingsPersistence
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @EnvironmentObject private var cloudAuthManager: CloudAuthManager
    
    var body: some View {
        Form {
            Section {
                if supabaseManager.isConfigured {
                    if supabaseManager.isAuthenticated {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Signed in as:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(supabaseManager.session?.user.email ?? "Unknown")
                                .font(.body)
                            
                            Button("Sign Out") {
                                Task {
                                    await supabaseManager.signOut()
                                }
                            }
                            .tooltip("Sign out from Supabase")
                        }
                    } else {
                        Text("Not signed in")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Supabase not configured")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Supabase Account")
            }
            
            Section {
                Toggle("Enable cloud sync", isOn: $appSettings.cloudSyncEnabled)
                    .tooltip("Sync projects with cloud storage")
                
                if appSettings.cloudSyncEnabled {
                    Toggle("Sync large media files", isOn: $appSettings.syncLargeFiles)
                        .tooltip("Include video files in cloud sync (uses more storage)")
                    
                    Stepper(value: $appSettings.syncInterval, in: 5...60, step: 5) {
                        Text("Sync every \(appSettings.syncInterval) minutes")
                            .tooltip("How often to sync with cloud")
                    }
                }
            } header: {
                Text("Sync Settings")
            }
            
            Section {
                ForEach(CloudSyncProvider.allCases, id: \.self) { provider in
                    HStack {
                        Image(systemName: provider.icon)
                        Text(provider.displayName)
                        Spacer()
                        if cloudAuthManager.hasConnectedAccount(for: provider) {
                            if let account = cloudAuthManager.account(for: provider) {
                                Text(account.email ?? account.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Button("Disconnect") {
                                    try? cloudAuthManager.disconnect(provider: provider)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                            }
                        } else {
                            Button("Connect") {
                                Task {
                                    try? await cloudAuthManager.connect(provider: provider)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Connected Services")
            }
        }
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsSection: View {
    @ObservedObject var appSettings: AppSettingsPersistence
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable debug logging", isOn: $appSettings.debugLoggingEnabled)
                    .tooltip("Log detailed debug information")
                
                Toggle("Show performance metrics", isOn: $appSettings.showPerformanceMetrics)
                    .tooltip("Display FPS and performance data")
                
                TextField("Cache directory", text: $appSettings.cacheDirectory)
                    .tooltip("Directory for temporary files")
                
                Button("Clear Cache") {
                    appSettings.clearCache()
                }
                .tooltip("Clear all cached data")
            } header: {
                Text("Diagnostics")
            }
            
            Section {
                Text("Version: \(appSettings.appVersion)")
                Text("Build: \(appSettings.buildNumber)")
                Text("Database: \(appSettings.databaseVersion)")
            } header: {
                Text("About")
            }
        }
        .padding()
    }
}


struct ShortcutAction: CaseIterable, Hashable {
    let id: String
    let title: String
    let description: String
    let currentShortcut: String
    
    static let allCases = [
        ShortcutAction(id: "newProject", title: "New Project", description: "Create a new project", currentShortcut: "⌘N"),
        ShortcutAction(id: "openProject", title: "Open Project", description: "Open an existing project", currentShortcut: "⌘O"),
        ShortcutAction(id: "saveProject", title: "Save Project", description: "Save the current project", currentShortcut: "⌘S"),
        ShortcutAction(id: "import", title: "Import Media", description: "Import media files", currentShortcut: "⌘I"),
        ShortcutAction(id: "walkthrough", title: "Walkthrough", description: "Show the interactive walkthrough", currentShortcut: "⌘⇧W"),
        ShortcutAction(id: "settings", title: "Settings", description: "Open settings", currentShortcut: "⌘,"),
        ShortcutAction(id: "filter", title: "Filter Clips", description: "Filter clips in the browser", currentShortcut: "⌘F"),
        ShortcutAction(id: "search", title: "Search", description: "Search clips and metadata", currentShortcut: "⌘K"),
    ]
}

// MARK: - Extensions

extension CloudSyncProvider {
    var icon: String {
        switch self {
        case .googleDrive: return "globe"
        case .dropbox: return "arrow.down.circle"
        case .amazonS3: return "archivebox"
        case .frameIO: return "film.stack"
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 800, height: 600)
    }
}
