# SLATE AI/ML Engine - User Guide

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [API Reference](#api-reference)
6. [Best Practices](#best-practices)
7. [Troubleshooting](#troubleshooting)

---

## Overview

SLATE AI/ML Engine is a powerful, production-ready system for automated video synchronization and AI-powered content analysis. It combines state-of-the-art machine learning with optimized signal processing to deliver professional-grade results.

### Key Features

- **Audio Synchronization**: Sub-frame accurate sync using multiple algorithms
- **AI Scoring**: Intelligent content analysis for quality assessment
- **Audio Role Classification**: Automatic identification of boom, lav, mix, and ISO tracks
- **Performance Optimization**: 50% faster than previous versions
- **Production Ready**: Comprehensive error handling and monitoring

---

## Installation

### System Requirements

- **macOS**: 14.0 or later
- **Memory**: 4GB RAM minimum (8GB recommended)
- **Storage**: 10GB free space
- **Processor**: Apple Silicon (M1/M2/M3) or Intel with Metal support

### Installing from Source

The **repository root** is the directory that contains `Package.swift`, `packages/`, `contracts/`, and `apps/desktop/` (there is no nested `slate/` folder).

```bash
git clone <your-remote-url> slate-engine
cd slate-engine

# Build all Swift packages (unified manifest at repo root)
./scripts/build.sh release

# Run tests to verify installation
./scripts/test.sh all
```

For the **macOS desktop app** only, open `apps/desktop/SLATE.xcodeproj` in Xcode or run:

`bash scripts/build-desktop-app.sh`

### Installing Binary Package

```bash
# Download the latest release
curl -L https://github.com/slate-ai/slate-engine/releases/latest/download/slate-engine-1.2.0-macos.tar.gz -o slate-engine.tar.gz

# Extract
tar -xzf slate-engine.tar.gz
cd slate-engine-1.2.0-macos

# Install to /usr/local
sudo cp -r bin /usr/local/
sudo cp -r lib /usr/local/
sudo cp -r config /usr/local/etc/slate/
```

---

## Quick Start

### Basic Synchronization

Use the `**SLATESyncEngine**` and `**SLATEAIPipeline**` modules directly from the Swift packages under `packages/`. The snippet below is illustrative; see the package APIs for current types.

```swift
import SLATESyncEngine

// Example: use SyncEngine from the sync-engine package
let syncEngine = SyncEngine()
// Wire audio URLs and run your sync workflow per SyncEngine docs.
```

### Command Line Usage

There is no single `slate-engine` shim in this repository. Use the **Swift packages** from your own tool or the **macOS app** for end-user flows. For headless ingest, the `slate-ingest` product is built from `packages/ingest-daemon` (see that package’s CLI target). The commands below are **illustrative** of the kind of workflow the libraries support; wire `SyncEngine` and `SLATEAIPipeline` in code instead of these exact flags.

```bash
# After building packages — conceptual example only (not installed as `slate-engine`):
# swift run --package-path packages/ingest-daemon slate-ingest …

# Develop and test sync/AI from SwiftPM:
# (cd packages/sync-engine && swift test)
# (cd packages/ai-pipeline && swift test)
```

---

## Configuration

### Configuration File

The engine uses a JSON configuration file. Default location: `/usr/local/etc/slate/slate-config.json`

```json
{
  "syncEngine": {
    "confidenceThresholds": {
      "high": 0.9,
      "medium": 0.7,
      "low": 0.5
    },
    "performance": {
      "maxConcurrentOperations": 4,
      "enableGPUAcceleration": true
    }
  },
  "aiPipeline": {
    "vision": {
      "sampleFPS": 2,
      "useCoreML": true
    },
    "transcription": {
      "model": "base",
      "language": "en"
    }
  },
  "logging": {
    "level": "info",
    "filePath": "/var/log/slate/engine.log"
  }
}
```

### Environment-Specific Configurations

- **Development**: `configs/development.json` - Relaxed thresholds, debug logging
- **Staging**: `configs/staging.json` - Production-like settings
- **Production**: `configs/production.json` - Optimized for performance

### Custom Configuration

```swift
// Load custom configuration
let config = try SLATEConfiguration.load(from: URL(fileURLWithPath: "my-config.json"))

// Create API with custom config
let slate = SLATEAPI(configuration: config)
```

---

## API Reference

### Core Classes

#### SLATEAPI

Main entry point for all SLATE operations.

```swift
public struct SLATEAPI {
    public init(configuration: SLATEConfiguration = .default)
    
    public func processClip(
        primaryAudio: URL,
        secondaryAudio: URL,
        proxyVideo: URL,
        fps: Double
    ) async throws -> ProcessedClipResult
    
    public func getSystemStatus() async -> SystemStatus
}
```

#### SyncEngineAPI

Audio synchronization functionality.

```swift
public struct SyncEngineAPI {
    public func syncClips(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> MultiCamSyncResult
    
    public func assignAudioRoles(tracks: [URL]) async throws -> [AudioTrack]
}
```

#### AIPipelineAPI

AI analysis and scoring.

```swift
public struct AIPipelineAPI {
    public func analyzeClip(_ clip: Clip) async throws -> ClipAnalysisResult
    
    public func getPerformanceReport() -> PerformanceReport
    
    public func getDegradationStatus() -> HealthReport
}
```

### Data Models

#### Clip

Represents a media clip with all metadata.

```swift
public struct Clip {
    public let id: String
    public let sourcePath: String
    public let proxyPath: String?
    public let duration: Double
    public let syncResult: SyncResult?
    public let aiScores: AIScores?
    // ... other properties
}
```

#### SyncResult

Results of synchronization operation.

```swift
public struct SyncResult {
    public let confidence: SyncConfidence
    public let method: SyncMethod
    public let offsetFrames: Int
}
```

#### AIScores

AI analysis results.

```swift
public struct AIScores {
    public let composite: Double
    public let vision: VisionScores
    public let audio: AudioScores
    public let performance: PerformanceScores
}
```

---

## Best Practices

### Performance Optimization

1. **Use Streaming for Large Files**
  ```swift
   // Files > 100MB automatically use streaming
   let config = SLATEConfiguration(
       syncEngine: .init(
           performance: .init(
               streamingMemoryLimit: 50_000_000
           )
       )
   )
  ```
2. **Enable GPU Acceleration**
  ```json
   {
     "syncEngine": {
       "performance": {
         "enableGPUAcceleration": true
       }
     }
   }
  ```
3. **Adjust Confidence Thresholds**
  - High quality footage: 0.9+ threshold
  - Documentary footage: 0.7+ threshold
  - Noisy environments: 0.5+ threshold

### Memory Management

1. **Use Object Pools**
  ```swift
   // Automatic with default configuration
   let poolManager = await PoolManager.shared
   let stats = await poolManager.getStatistics()
  ```
2. **Monitor Memory Usage**
  ```swift
   let status = await slate.getSystemStatus()
   print("Memory usage: \(status.metrics.memoryUsage)")
  ```

### Error Handling

1. **Always Handle Errors Gracefully**
  ```swift
   do {
       let result = try await slate.processClip(...)
   } catch SyncEngineAPI.SyncError.insufficientData {
       // Handle short audio files
   } catch SyncEngineAPI.SyncError.timeout {
       // Handle long processing times
   } catch {
       // Handle other errors
   }
  ```
2. **Use Graceful Degradation**
  ```swift
   // System automatically falls back when models fail
   let degradation = await aiAPI.getDegradationStatus()
   if degradation.level != .normal {
       print("Using fallback processing")
   }
  ```

### Batch Processing

1. **Process Multiple Clips Efficiently**
  ```swift
   let results = try await withThrowingTaskGroup(of: ProcessedClipResult.self) { group in
       for clip in clips {
           group.addTask {
               try await slate.processClip(...)
           }
       }
       return try await group.reduce(into: []) { $0.append($1) }
   }
  ```
2. **Use Caching for Repeated Analysis**
  ```swift
   // Automatic with default configuration
   let cache = await CacheManager.shared.getAIScoreCache()
   // Results are cached for 1 hour by default
  ```

---

## Troubleshooting

### Common Issues

#### Sync Fails with "Insufficient Data"

**Cause**: Audio files too short (< 1 second)
**Solution**: 

- Ensure audio files are at least 1 second long
- Check file integrity with `file` command

#### AI Analysis Returns Low Scores

**Cause**: Poor quality video/audio or missing proxy
**Solution**:

- Verify proxy video exists and is accessible
- Check video quality (resolution, frame rate)
- Review confidence metrics in logs

#### Processing is Slow

**Cause**: Insufficient resources or large files
**Solution**:

- Increase memory limits in configuration
- Enable GPU acceleration
- Use streaming for very large files

#### Memory Usage High

**Cause**: Processing multiple large files simultaneously
**Solution**:

- Reduce `maxConcurrentOperations`
- Enable object pooling
- Monitor with `getSystemStatus()`

### Debug Mode

Enable debug logging for detailed information:

```json
{
  "logging": {
    "level": "debug",
    "structured": true,
    "enableMetrics": true
  }
}
```

### Performance Monitoring

```swift
// Get real-time metrics
let status = await slate.getSystemStatus()
print("Average sync time: \(status.metrics.performanceMetrics["sync"]?.averageDuration ?? 0)s")
print("Cache hit rate: \(status.cacheStatistics.syncCache?.hitRate ?? 0)")
```

### Getting Help

1. **Check Logs**: `/var/log/slate/engine.log`
2. **Run Diagnostics**: `slate-engine --diagnostics`
3. **Review Configuration**: `slate-engine --config-check`
4. **Contact Support**: [support@slate.ai](mailto:support@slate.ai)

---

## Advanced Topics

### Custom Models

Add custom ML models to `/opt/slate/models/`:

```swift
// Model automatically detected and loaded
let modelManager = CoreMLModelManager()
try await modelManager.loadModels()
```

### Plugin Architecture

Extend functionality with plugins:

```swift
protocol SLATEPlugin {
    var name: String { get }
    func process(_ clip: Clip) async throws -> PluginResult
}
```

### Real-time Processing

For live production workflows:

```swift
// Use streaming mode for real-time sync
let processor = StreamingAudioProcessor()
let result = try await processor.correlateStreaming(...)
```

---

## Version History

See [CHANGELOG.md](../CHANGELOG.md) for detailed version history.

### v1.2.0 (Current)

- 50% performance improvement
- CoreML integration
- Production-ready features

### v1.1.0

- Basic sync engine
- Initial AI pipeline

### v1.0.0

- Proof of concept

---

## License

SLATE AI/ML Engine is licensed under the MIT License. See [LICENSE](../LICENSE) for details.

---

## Support

- **Documentation**: [https://docs.slate.ai](https://docs.slate.ai)
- **GitHub**: [https://github.com/slate-ai/slate-engine](https://github.com/slate-ai/slate-engine)
- **Email**: [support@slate.ai](mailto:support@slate.ai)
- **Discord**: [https://discord.gg/slate](https://discord.gg/slate)

