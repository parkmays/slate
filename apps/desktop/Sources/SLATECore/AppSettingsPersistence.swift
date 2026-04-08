// SLATE — AppSettingsPersistence
// Owned by: Claude Code
//
// Global app settings persistence using UserDefaults.
// Handles user preferences that apply across all projects.

import Foundation
import SwiftUI
import SLATESharedTypes
import os.log

@MainActor
public final class AppSettingsPersistence: ObservableObject {
    private static let defaultsKey = "SLATE.appSettings.v1"
    private static let logger = Logger(subsystem: "com.mountaintop.slate", category: "AppSettingsPersistence")
    
    // MARK: - Published Properties
    
    // General Settings
    @Published public var defaultProjectMode: ProjectMode = .narrative
    @Published public var autoSaveEnabled: Bool = true
    @Published public var autoSaveInterval: Int = 120
    @Published public var clipNameFormat: String = "{scene}_{take}_{camera}"
    @Published public var timecodeFormat: TimecodeFormat = .dropFrame
    
    // Processing Settings
    @Published public var generateProxies: Bool = true
    @Published public var proxyResolution: ProxyResolution = .hd720
    @Published public var proxyBurnInTimecode: Bool = false
    @Published public var aiScoringEnabled: Bool = true
    @Published public var faceDetectionEnabled: Bool = true
    @Published public var transcriptionEnabled: Bool = true
    @Published public var maxConcurrentJobs: Double = 4
    @Published public var processingPriority: ProcessingPriority = .normal
    
    // Interface Settings
    @Published public var appearance: Appearance = .system
    @Published public var uiScale: Double = 1.0
    @Published public var showTooltips: Bool = true
    @Published public var showShortcutsInTooltips: Bool = true
    @Published public var animationsEnabled: Bool = true
    @Published public var customToolbarItems: String = "new,import,filter,search,ingest,walkthrough"
    @Published public var showToolbarLabels: Bool = true
    
    // Cloud Settings
    @Published public var cloudSyncEnabled: Bool = false
    @Published public var syncLargeFiles: Bool = false
    @Published public var syncInterval: Int = 15
    
    // Advanced Settings
    @Published public var debugLoggingEnabled: Bool = false
    @Published public var showPerformanceMetrics: Bool = false
    @Published public var cacheDirectory: String = ""
    
    // Read-only properties
    public let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    public let buildNumber: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    public let databaseVersion: String = "1.0"
    
    // MARK: - Init
    
    public init() {
        loadSettings()
    }
    
    // MARK: - Save/Load
    
    public func saveSettings() {
        let settings = SettingsData(
            defaultProjectMode: defaultProjectMode,
            autoSaveEnabled: autoSaveEnabled,
            autoSaveInterval: autoSaveInterval,
            clipNameFormat: clipNameFormat,
            timecodeFormat: timecodeFormat,
            generateProxies: generateProxies,
            proxyResolution: proxyResolution,
            proxyBurnInTimecode: proxyBurnInTimecode,
            aiScoringEnabled: aiScoringEnabled,
            faceDetectionEnabled: faceDetectionEnabled,
            transcriptionEnabled: transcriptionEnabled,
            maxConcurrentJobs: maxConcurrentJobs,
            processingPriority: processingPriority,
            appearance: appearance,
            uiScale: uiScale,
            showTooltips: showTooltips,
            showShortcutsInTooltips: showShortcutsInTooltips,
            animationsEnabled: animationsEnabled,
            customToolbarItems: customToolbarItems,
            showToolbarLabels: showToolbarLabels,
            cloudSyncEnabled: cloudSyncEnabled,
            syncLargeFiles: syncLargeFiles,
            syncInterval: syncInterval,
            debugLoggingEnabled: debugLoggingEnabled,
            showPerformanceMetrics: showPerformanceMetrics,
            cacheDirectory: cacheDirectory
        )
        
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            Self.logger.info("App settings saved successfully")
        } catch {
            Self.logger.error("Failed to save app settings: \(error.localizedDescription)")
        }
    }
    
    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            Self.logger.debug("No saved app settings found, using defaults")
            return
        }
        
        do {
            let settings = try JSONDecoder().decode(SettingsData.self, from: data)
            
            // Apply loaded settings
            defaultProjectMode = settings.defaultProjectMode
            autoSaveEnabled = settings.autoSaveEnabled
            autoSaveInterval = settings.autoSaveInterval
            clipNameFormat = settings.clipNameFormat
            timecodeFormat = settings.timecodeFormat
            
            generateProxies = settings.generateProxies
            proxyResolution = settings.proxyResolution
            proxyBurnInTimecode = settings.proxyBurnInTimecode
            aiScoringEnabled = settings.aiScoringEnabled
            faceDetectionEnabled = settings.faceDetectionEnabled
            transcriptionEnabled = settings.transcriptionEnabled
            maxConcurrentJobs = settings.maxConcurrentJobs
            processingPriority = settings.processingPriority
            
            appearance = settings.appearance
            uiScale = settings.uiScale
            showTooltips = settings.showTooltips
            showShortcutsInTooltips = settings.showShortcutsInTooltips
            animationsEnabled = settings.animationsEnabled
            customToolbarItems = settings.customToolbarItems
            showToolbarLabels = settings.showToolbarLabels
            
            cloudSyncEnabled = settings.cloudSyncEnabled
            syncLargeFiles = settings.syncLargeFiles
            syncInterval = settings.syncInterval
            
            debugLoggingEnabled = settings.debugLoggingEnabled
            showPerformanceMetrics = settings.showPerformanceMetrics
            cacheDirectory = settings.cacheDirectory.isEmpty ? defaultCacheDirectory() : settings.cacheDirectory
            
            Self.logger.info("App settings loaded successfully")
        } catch {
            Self.logger.error("Failed to load app settings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Actions
    
    public func resetToDefaults() {
        // Reset to default values
        defaultProjectMode = .narrative
        autoSaveEnabled = true
        autoSaveInterval = 120
        clipNameFormat = "{scene}_{take}_{camera}"
        timecodeFormat = .dropFrame
        
        generateProxies = true
        proxyResolution = .hd720
        proxyBurnInTimecode = false
        aiScoringEnabled = true
        faceDetectionEnabled = true
        transcriptionEnabled = true
        maxConcurrentJobs = 4
        processingPriority = .normal
        
        appearance = .system
        uiScale = 1.0
        showTooltips = true
        showShortcutsInTooltips = true
        animationsEnabled = true
        customToolbarItems = "new,import,filter,search,ingest,walkthrough"
        showToolbarLabels = true
        
        cloudSyncEnabled = false
        syncLargeFiles = false
        syncInterval = 15
        
        debugLoggingEnabled = false
        showPerformanceMetrics = false
        cacheDirectory = defaultCacheDirectory()
        
        saveSettings()
        Self.logger.info("App settings reset to defaults")
    }
    
    public func clearCache() {
        let fileManager = FileManager.default
        
        // Clear cache directory
        if !cacheDirectory.isEmpty {
            do {
                let cacheURL = URL(fileURLWithPath: cacheDirectory)
                if fileManager.fileExists(atPath: cacheURL.path) {
                    let contents = try fileManager.contentsOfDirectory(at: cacheURL, 
                                                                   includingPropertiesForKeys: nil)
                    for url in contents {
                        try fileManager.removeItem(at: url)
                    }
                    Self.logger.info("Cache directory cleared: \(self.cacheDirectory)")
                }
            } catch {
                Self.logger.error("Failed to clear cache directory: \(error.localizedDescription)")
            }
        }
        
        // Clear system cache
        let tempDir = NSTemporaryDirectory()
        if let cacheURLs = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: tempDir),
                                                               includingPropertiesForKeys: nil) {
            for url in cacheURLs {
                if url.lastPathComponent.hasPrefix("SLATE") {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
    
    private func defaultCacheDirectory() -> String {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths.first!.appendingPathComponent("com.mountaintop.slate")
        return cacheDir.path
    }
}

// MARK: - Settings Data

private struct SettingsData: Codable {
    let defaultProjectMode: ProjectMode
    let autoSaveEnabled: Bool
    let autoSaveInterval: Int
    let clipNameFormat: String
    let timecodeFormat: TimecodeFormat
    
    let generateProxies: Bool
    let proxyResolution: ProxyResolution
    let proxyBurnInTimecode: Bool
    let aiScoringEnabled: Bool
    let faceDetectionEnabled: Bool
    let transcriptionEnabled: Bool
    let maxConcurrentJobs: Double
    let processingPriority: ProcessingPriority
    
    let appearance: Appearance
    let uiScale: Double
    let showTooltips: Bool
    let showShortcutsInTooltips: Bool
    let animationsEnabled: Bool
    let customToolbarItems: String
    let showToolbarLabels: Bool
    
    let cloudSyncEnabled: Bool
    let syncLargeFiles: Bool
    let syncInterval: Int
    
    let debugLoggingEnabled: Bool
    let showPerformanceMetrics: Bool
    let cacheDirectory: String
}

// MARK: - Supporting Types

public enum Appearance: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

public enum ProxyResolution: String, CaseIterable, Codable {
    case sd540 = "540p"
    case hd720 = "720p"
    case hd1080 = "1080p"
}

public enum TimecodeFormat: String, CaseIterable, Codable {
    case dropFrame = "df"
    case nonDropFrame = "ndf"
    case seconds = "seconds"
}

public enum ProcessingPriority: String, CaseIterable, Codable {
    case low = "low"
    case normal = "normal"
    case high = "high"
}
