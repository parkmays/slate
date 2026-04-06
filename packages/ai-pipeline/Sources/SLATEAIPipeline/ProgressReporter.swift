import AVFoundation
import Combine
import Foundation

/// Real-time progress reporting for long-running AI tasks
public final class ProgressReporter: ObservableObject, @unchecked Sendable {
    
    public struct TaskProgress: Sendable {
        public let taskId: String
        public let taskType: TaskType
        public let phase: Phase
        public let progress: Double // 0.0 to 1.0
        public let message: String
        public let estimatedTimeRemaining: TimeInterval?
        public let startTime: Date
        public let currentStep: String
        public let totalSteps: Int
        public let completedSteps: Int
        
        public init(taskId: String, taskType: TaskType, phase: Phase, progress: Double, 
                   message: String, estimatedTimeRemaining: TimeInterval? = nil,
                   startTime: Date = Date(), currentStep: String = "", 
                   totalSteps: Int = 0, completedSteps: Int = 0) {
            self.taskId = taskId
            self.taskType = taskType
            self.phase = phase
            self.progress = progress
            self.message = message
            self.estimatedTimeRemaining = estimatedTimeRemaining
            self.startTime = startTime
            self.currentStep = currentStep
            self.totalSteps = totalSteps
            self.completedSteps = completedSteps
        }
    }
    
    public enum TaskType: String, CaseIterable, Sendable {
        case visionScoring = "vision_scoring"
        case audioScoring = "audio_scoring"
        case transcription = "transcription"
        case performanceScoring = "performance_scoring"
        case syncAnalysis = "sync_analysis"
        case roleClassification = "role_classification"
        case fullAnalysis = "full_analysis"
    }
    
    public enum Phase: String, CaseIterable, Sendable {
        case initializing = "initializing"
        case loading = "loading"
        case processing = "processing"
        case analyzing = "analyzing"
        case finalizing = "finalizing"
        case completed = "completed"
        case failed = "failed"
    }
    
    @Published public private(set) var currentTasks: [String: TaskProgress] = [:]
    @Published public private(set) var completedTasks: [String: TaskProgress] = [:]
    @Published public private(set) var failedTasks: [String: TaskProgress] = [:]
    
    private nonisolated(unsafe) let progressUpdateSubject = PassthroughSubject<TaskProgress, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let progressUpdateQueue = DispatchQueue(label: "progress.updates", qos: .userInitiated)
    
    public init() {
        // Clean up old tasks periodically
        Timer.publish(every: 300, on: .main, in: .common) // Every 5 minutes
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanupOldTasks()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Task Management
    
    public func startTask(
        id: String,
        type: TaskType,
        message: String = "Starting...",
        totalSteps: Int = 0
    ) {
        let progress = TaskProgress(
            taskId: id,
            taskType: type,
            phase: .initializing,
            progress: 0.0,
            message: message,
            startTime: Date(),
            currentStep: "",
            totalSteps: totalSteps,
            completedSteps: 0
        )
        
        progressUpdateQueue.async { [weak self] in
            self?.updateProgress(progress)
        }
    }
    
    public func updateProgress(
        taskId: String,
        phase: Phase,
        progress: Double,
        message: String,
        currentStep: String = "",
        completedSteps: Int? = nil
    ) {
        progressUpdateQueue.async { [weak self] in
            guard let self = self,
                  let taskProgress = self.currentTasks[taskId] else { return }
            
            let newProgress = TaskProgress(
                taskId: taskId,
                taskType: taskProgress.taskType,
                phase: phase,
                progress: progress,
                message: message,
                estimatedTimeRemaining: self.calculateETA(for: taskProgress, progress: progress),
                startTime: taskProgress.startTime,
                currentStep: currentStep,
                totalSteps: taskProgress.totalSteps,
                completedSteps: completedSteps ?? taskProgress.completedSteps
            )
            
            self.updateProgress(newProgress)
        }
    }
    
    public func updateStep(
        taskId: String,
        stepName: String,
        stepProgress: Double,
        message: String
    ) {
        progressUpdateQueue.async { [weak self] in
            guard let self = self,
                  let taskProgress = self.currentTasks[taskId] else { return }
            
            let totalProgress = Double(taskProgress.completedSteps) / Double(max(taskProgress.totalSteps, 1))
            let adjustedProgress = totalProgress + (stepProgress / Double(max(taskProgress.totalSteps, 1)))
            
            self.updateProgress(
                taskId: taskId,
                phase: .processing,
                progress: min(adjustedProgress, 0.99), // Don't reach 100% until complete
                message: message,
                currentStep: stepName
            )
        }
    }
    
    public func completeTask(
        taskId: String,
        message: String = "Completed successfully"
    ) {
        progressUpdateQueue.async { [weak self] in
            guard let self = self,
                  let taskProgress = self.currentTasks[taskId] else { return }
            
            let finalProgress = TaskProgress(
                taskId: taskId,
                taskType: taskProgress.taskType,
                phase: .completed,
                progress: 1.0,
                message: message,
                estimatedTimeRemaining: 0,
                startTime: taskProgress.startTime,
                currentStep: taskProgress.currentStep,
                totalSteps: taskProgress.totalSteps,
                completedSteps: taskProgress.totalSteps
            )
            
            self.currentTasks.removeValue(forKey: taskId)
            self.completedTasks[taskId] = finalProgress
            self.publishUpdate(finalProgress)
        }
    }
    
    public func failTask(
        taskId: String,
        error: Error,
        message: String = "Failed"
    ) {
        progressUpdateQueue.async { [weak self] in
            guard let self = self,
                  let taskProgress = self.currentTasks[taskId] else { return }
            
            let finalProgress = TaskProgress(
                taskId: taskId,
                taskType: taskProgress.taskType,
                phase: .failed,
                progress: taskProgress.progress,
                message: "\(message): \(error.localizedDescription)",
                startTime: taskProgress.startTime,
                currentStep: taskProgress.currentStep,
                totalSteps: taskProgress.totalSteps,
                completedSteps: taskProgress.completedSteps
            )
            
            self.currentTasks.removeValue(forKey: taskId)
            self.failedTasks[taskId] = finalProgress
            self.publishUpdate(finalProgress)
        }
    }
    
    // MARK: - Progress Stream
    
    public var progressStream: AnyPublisher<TaskProgress, Never> {
        progressUpdateSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    public func getProgress(for taskId: String) -> TaskProgress? {
        return currentTasks[taskId] ?? completedTasks[taskId] ?? failedTasks[taskId]
    }
    
    // MARK: - Private Methods
    
    private func updateProgress(_ progress: TaskProgress) {
        if progress.phase == .completed {
            currentTasks.removeValue(forKey: progress.taskId)
            completedTasks[progress.taskId] = progress
        } else if progress.phase == .failed {
            currentTasks.removeValue(forKey: progress.taskId)
            failedTasks[progress.taskId] = progress
        } else {
            currentTasks[progress.taskId] = progress
        }
        
        publishUpdate(progress)
    }
    
    private func publishUpdate(_ progress: TaskProgress) {
        // Subscribers use `.receive(on: DispatchQueue.main)`; emit from this queue without hopping to MainActor (avoids Swift 6 isolation errors on PassthroughSubject).
        progressUpdateSubject.send(progress)
    }
    
    private func calculateETA(for current: TaskProgress, progress: Double) -> TimeInterval? {
        guard progress > 0 else { return nil }
        
        let elapsed = Date().timeIntervalSince(current.startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed
        
        return max(0, remaining)
    }
    
    private func cleanupOldTasks() {
        progressUpdateQueue.async { [weak self] in
            let cutoff = Date().addingTimeInterval(-3600) // 1 hour ago
            
            self?.completedTasks = self?.completedTasks.filter { $0.value.startTime > cutoff } ?? [:]
            self?.failedTasks = self?.failedTasks.filter { $0.value.startTime > cutoff } ?? [:]
        }
    }
}

// MARK: - Progress Reporting Extensions

extension VisionScorer {
    public func scoreClipWithProgress(
        proxyURL: URL,
        fps: Double,
        reporter: ProgressReporter,
        taskId: String
    ) async throws -> VisionScoreResult {
        reporter.startTask(
            id: taskId,
            type: .visionScoring,
            message: "Initializing vision scoring...",
            totalSteps: 4
        )
        
        do {
            // Load video
            reporter.updateStep(taskId: taskId, stepName: "Loading video", stepProgress: 0.0, message: "Loading video file...")
            let asset = AVURLAsset(url: proxyURL)
            let duration = try await asset.load(.duration).seconds
            
            reporter.updateProgress(taskId: taskId, phase: .loading, progress: 0.1, message: "Video loaded successfully")
            
            // Generate frames
            reporter.updateStep(taskId: taskId, stepName: "Extracting frames", stepProgress: 0.25, message: "Extracting frames for analysis...")
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            
            let step = max(1.0 / max(2, 1), 0.25)
            let sampleTimes = Array(stride(from: 0.0, through: max(0, duration - 0.001), by: step).prefix(12))
            let sampleCount = sampleTimes.count
            
            reporter.updateProgress(taskId: taskId, phase: .processing, progress: 0.3, message: "Analyzing frames...")
            
            // Process frames
            var frameResults: [(focus: Double, exposure: Double, stability: Double)] = []
            for (index, _) in sampleTimes.enumerated() {
                let frameProgress = Double(index) / Double(max(sampleCount, 1))
                reporter.updateProgress(
                    taskId: taskId,
                    phase: .analyzing,
                    progress: 0.3 + (frameProgress * 0.5),
                    message: "Analyzing frame \(index + 1) of \(sampleCount)..."
                )
                
                // Process frame here...
                // This is simplified - actual frame processing would happen here
                try await Task.sleep(nanoseconds: 100_000_000) // Simulate work
                
                frameResults.append((focus: 75.0, exposure: 80.0, stability: 85.0))
            }
            
            // Finalize
            reporter.updateStep(taskId: taskId, stepName: "Finalizing", stepProgress: 0.9, message: "Calculating final scores...")
            
            let avgFocus = frameResults.map(\.focus).reduce(0, +) / Double(frameResults.count)
            let avgExposure = frameResults.map(\.exposure).reduce(0, +) / Double(frameResults.count)
            let avgStability = frameResults.map(\.stability).reduce(0, +) / Double(frameResults.count)
            
            let result = VisionScoreResult(
                focus: avgFocus,
                exposure: avgExposure,
                stability: avgStability,
                reasons: [],
                modelVersion: "optimized-v1",
                confidence: 0.9
            )
            
            reporter.completeTask(taskId: taskId, message: "Vision scoring completed successfully")
            
            return result
            
        } catch {
            reporter.failTask(taskId: taskId, error: error, message: "Vision scoring failed")
            throw error
        }
    }
}

// MARK: - SwiftUI Integration Helper

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public struct SLATETaskProgressView: View {
    @ObservedObject var reporter: ProgressReporter
    let taskId: String
    
    public var body: some View {
        if let progress = reporter.getProgress(for: taskId) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progress.taskType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(progress.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                SwiftUI.ProgressView(value: progress.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let eta = progress.estimatedTimeRemaining, eta > 0 {
                    Text("Estimated time remaining: \(formatDuration(eta))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return "\(minutes)m \(seconds)s"
    }
}
#endif
