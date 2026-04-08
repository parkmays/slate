// SLATE — ProgressWithETA
// Owned by: Claude Code
//
// Enhanced progress view with ETA calculations using exponential moving average.
// Provides smooth time estimates and speed calculations for processing tasks.

import SwiftUI
import SLATECore
import SLATESharedTypes
import Combine

struct ProgressWithETA: View {
    let progress: Double
    let startTime: Date
    let totalSize: Int64?
    let processedSize: Int64?
    let stage: String
    let isActive: Bool
    
    @StateObject private var etaCalculator = ETACalculator()
    @State private var eta: String?
    @State private var speed: String?
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Progress bar
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: stageColor))
                .frame(width: 120)
            
            // Percentage
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // ETA and speed (if available)
            if let eta = eta, progress > 0.1 {
                Text(eta)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let speed = speed {
                    Text(speed)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onReceive(timer) { _ in
            updateETA()
        }
        .onChange(of: progress) {
            etaCalculator.updateProgress(progress: progress, at: Date())
            updateETA()
        }
        .onAppear {
            etaCalculator.start(totalSize: totalSize, startTime: startTime)
        }
    }
    
    private func updateETA() {
        guard isActive && progress > 0.01 else {
            eta = nil
            speed = nil
            return
        }
        
        if let estimate = etaCalculator.calculateETA() {
            eta = formatDuration(estimate)
        }
        
        if let rate = etaCalculator.calculateRate() {
            speed = formatSpeed(rate)
        }
    }
    
    private var stageColor: Color {
        switch stage.lowercased() {
        case "checksum": return .blue
        case "copy": return .green
        case "verify": return .orange
        case "proxy": return .purple
        case "sync": return .teal
        case "complete": return .green
        case "error": return .red
        default: return .primary
        }
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "0s"
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

// MARK: - ETA Calculator

class ETACalculator: ObservableObject {
    private var totalSize: Int64?
    private var startTime: Date?
    private var progressHistory: [(progress: Double, time: Date)] = []
    private var speedHistory: [Double] = []
    private let alpha: Double = 0.3 // EMA smoothing factor
    
    func start(totalSize: Int64?, startTime: Date) {
        self.totalSize = totalSize
        self.startTime = startTime
        self.progressHistory = []
        self.speedHistory = []
    }
    
    func updateProgress(progress: Double, at time: Date) {
        progressHistory.append((progress: progress, time: time))
        
        // Keep only recent history (last 10 data points)
        if progressHistory.count > 10 {
            progressHistory.removeFirst()
        }
        
        // Calculate current speed
        if let last = progressHistory.secondLast {
            let timeDelta = time.timeIntervalSince(last.time)
            let progressDelta = progress - last.progress
            
            if timeDelta > 0 {
                let currentSpeed = progressDelta / timeDelta
                updateSpeedEMA(currentSpeed)
            }
        }
    }
    
    func calculateETA() -> TimeInterval? {
        guard let currentSpeed = speedHistory.last,
              currentSpeed > 0,
              let last = progressHistory.last else {
            return nil
        }
        
        let remainingProgress = 1.0 - last.progress
        let estimatedTime = remainingProgress / currentSpeed
        
        // Only show ETA if progress is at least 10% complete
        guard last.progress > 0.1 else { return nil }
        
        return estimatedTime
    }
    
    func calculateRate() -> Double? {
        guard let totalSize = totalSize,
              let currentSpeed = speedHistory.last else {
            return nil
        }
        
        return Double(totalSize) * currentSpeed
    }
    
    private func updateSpeedEMA(_ newSpeed: Double) {
        if let lastSpeed = speedHistory.last {
            let ema = alpha * newSpeed + (1 - alpha) * lastSpeed
            speedHistory.append(ema)
        } else {
            speedHistory.append(newSpeed)
        }
        
        // Keep only recent speeds
        if speedHistory.count > 10 {
            speedHistory.removeFirst()
        }
    }
}

// MARK: - Enhanced Ingest Progress Row

struct EnhancedIngestProgressRow: View {
    let item: IngestProgressItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Stage icon with animation
            ZStack {
                Circle()
                    .fill(stageColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: item.stage.iconName)
                    .foregroundColor(stageColor)
                    .font(.system(size: 16, weight: .medium))
                    .rotationEffect(.degrees(item.stage == IngestStage.sync ? 360 : 0))
                    .animation(
                        item.stage == IngestStage.sync ? 
                        .linear(duration: 2).repeatForever(autoreverses: false) : 
                        .default,
                        value: item.stage
                    )
            }
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(.body)
                    .lineLimit(1)
                    .help(item.filename)
                
                HStack(spacing: 8) {
                    Text(item.stage.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress with ETA
            ProgressWithETA(
                progress: item.progress,
                startTime: Date(),
                totalSize: nil,
                processedSize: nil,
                stage: item.stage.rawValue,
                isActive: item.stage != .complete && item.stage != .error
            )
        }
        .padding(.vertical, 8)
        .background(item.stage == .error ? Color.red.opacity(0.05) : Color.clear)
        .cornerRadius(4)
    }
    
    private var stageColor: Color {
        switch item.stage {
        case .checksum: return .blue
        case .copy: return .green
        case .verify: return .orange
        case .proxy: return .purple
        case .sync: return .teal
        case .complete: return .green
        case .error: return .red
        }
    }
}

// MARK: - Extensions

extension Array {
    var secondLast: Element? {
        guard count >= 2 else { return nil }
        return self[index(count, offsetBy: -2)]
    }
}

