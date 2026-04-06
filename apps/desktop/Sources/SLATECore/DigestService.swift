// SLATE — Daily end-of-day digest (email / Slack) for off-set producers.

import Foundation
import SLATESharedTypes

// MARK: - Report models

public struct DigestReport: Sendable {
    public let projectName: String
    public let date: String
    public let totalClipsIngested: Int
    public let totalDurationMinutes: Double
    public let averageCompositeScore: Double
    public let topTakes: [DigestTake]
    public let flaggedTakes: [DigestTake]
    public let circledTakes: [DigestTake]
    public let scenesCompleted: [String]
    public let scenesContinued: [String]

    public init(
        projectName: String,
        date: String,
        totalClipsIngested: Int,
        totalDurationMinutes: Double,
        averageCompositeScore: Double,
        topTakes: [DigestTake],
        flaggedTakes: [DigestTake],
        circledTakes: [DigestTake],
        scenesCompleted: [String],
        scenesContinued: [String]
    ) {
        self.projectName = projectName
        self.date = date
        self.totalClipsIngested = totalClipsIngested
        self.totalDurationMinutes = totalDurationMinutes
        self.averageCompositeScore = averageCompositeScore
        self.topTakes = topTakes
        self.flaggedTakes = flaggedTakes
        self.circledTakes = circledTakes
        self.scenesCompleted = scenesCompleted
        self.scenesContinued = scenesContinued
    }
}

public struct DigestTake: Sendable {
    public let clipId: String
    public let label: String
    public let compositeScore: Double
    public let reasonSummary: String
    public let proxyThumbnailURL: String?

    public init(
        clipId: String,
        label: String,
        compositeScore: Double,
        reasonSummary: String,
        proxyThumbnailURL: String?
    ) {
        self.clipId = clipId
        self.label = label
        self.compositeScore = compositeScore
        self.reasonSummary = reasonSummary
        self.proxyThumbnailURL = proxyThumbnailURL
    }
}

// MARK: - Digest service

@MainActor
private final class DigestTimerStorage {
    static let shared = DigestTimerStorage()
    var timers: [String: Timer] = [:]
}

public actor DigestService {
    public static let shared = DigestService()
    private static let lastSentKeyPrefix = "SLATE.digest.lastSentDate."

    /// Registers a timer so the digest runs at `sendAt` local hour (default 9 PM), then every 24 hours.
    /// If the app exits before fire, no digest is sent.
    public func scheduleDailyDigest(for project: Project, sendAt hour: Int = 21, clipStore: GRDBClipStore) async {
        let scheduleHour = min(23, max(0, hour))
        let interval = Self.secondsUntilNextLocalHour(scheduleHour, minute: 0)
        await scheduleDigestTimer(projectId: project.id, clipStore: clipStore, fireAfter: interval)
    }

    /// Exposed for tests and debugging — same text sent via SendGrid.
    public static func plainTextEmailBody(for report: DigestReport) -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════")
        lines.append("SLATE DAILY DIGEST — \(report.projectName)")
        lines.append(
            "\(report.date) | \(report.totalClipsIngested) clips | \(String(format: "%.1f", report.totalDurationMinutes)) min | Avg score: \(String(format: "%.0f", report.averageCompositeScore))/100"
        )
        lines.append("═══════════════════════════")
        lines.append("")
        lines.append("✅ CIRCLED TAKES (\(report.circledTakes.count))")
        for t in report.circledTakes {
            lines.append("\(t.label) — \(String(format: "%.0f", t.compositeScore))/100")
        }
        lines.append("")
        lines.append("⭐ TOP TAKES (\(report.topTakes.count))")
        for t in report.topTakes {
            lines.append("\(t.label) — \(String(format: "%.0f", t.compositeScore))/100 — \(t.reasonSummary)")
        }
        lines.append("")
        lines.append("⚠️  FLAGGED TAKES (\(report.flaggedTakes.count))")
        for t in report.flaggedTakes {
            lines.append("\(t.label) — \(String(format: "%.0f", t.compositeScore))/100 — \(t.reasonSummary)")
        }
        lines.append("")
        lines.append("📋 SCENE COVERAGE")
        lines.append("Completed: \(report.scenesCompleted.joined(separator: ", "))")
        lines.append("In progress: \(report.scenesContinued.joined(separator: ", "))")
        lines.append("─────────────────────────────")
        lines.append("Powered by SLATE · Mountain Top Pictures")
        return lines.joined(separator: "\n")
    }

    /// Next fire after `interval` seconds; when the timer fires, the digest runs and a new 24-hour timer is registered.
    private func scheduleDigestTimer(projectId: String, clipStore: GRDBClipStore, fireAfter interval: TimeInterval) async {
        await MainActor.run {
            DigestTimerStorage.shared.timers[projectId]?.invalidate()
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak clipStore] _ in
                guard let clipStore else { return }
                Task {
                    await DigestService.shared.handleDigestTimerFired(projectId: projectId, clipStore: clipStore)
                }
            }
            RunLoop.main.add(t, forMode: .common)
            DigestTimerStorage.shared.timers[projectId] = t
        }
    }

    fileprivate func handleDigestTimerFired(projectId: String, clipStore: GRDBClipStore) async {
        guard let proj = await clipStore.project(byId: projectId),
              proj.dailyDigestEnabled,
              !proj.digestTargets.isEmpty
        else {
            await cancelDigestSchedule(forProjectId: projectId)
            return
        }
        await runScheduledDigest(projectId: projectId, clipStore: clipStore)
        guard let projAfter = await clipStore.project(byId: projectId),
              projAfter.dailyDigestEnabled,
              !projAfter.digestTargets.isEmpty
        else {
            await cancelDigestSchedule(forProjectId: projectId)
            return
        }
        await scheduleDigestTimer(projectId: projectId, clipStore: clipStore, fireAfter: 24 * 3600)
    }

    public func cancelDigestSchedule(forProjectId projectId: String) async {
        await MainActor.run {
            DigestTimerStorage.shared.timers[projectId]?.invalidate()
            DigestTimerStorage.shared.timers[projectId] = nil
        }
    }

    public func generateDigest(for projectId: String, clips: [Clip], projectName: String, referenceDate: Date = Date()) -> DigestReport {
        let dayClips = clips.filter { $0.projectId == projectId && Self.isIngestedOnSameCalendarDay($0.ingestedAt, as: referenceDate) }

        let totalClipsIngested = dayClips.count
        let totalDurationMinutes = dayClips.reduce(0.0) { $0 + $1.duration } / 60.0

        let scored = dayClips.compactMap { c -> (Clip, Double)? in
            guard let comp = c.aiScores?.composite else { return nil }
            return (c, comp)
        }
        let averageCompositeScore: Double = {
            guard !scored.isEmpty else { return 0 }
            return scored.map(\.1).reduce(0, +) / Double(scored.count)
        }()

        let sortedByScore = scored.sorted { $0.1 > $1.1 }
        let topRaw = sortedByScore.prefix(5)
        let topTakes = topRaw.map { Self.digestTake(from: $0.0, compositeOverride: $0.1) }

        let flaggedSource = dayClips.filter(Self.isFlaggedTake(_:))
        let flaggedTakes = flaggedSource.map { Self.digestTake(from: $0, compositeOverride: $0.aiScores?.composite ?? 0) }

        let circled = dayClips.filter { $0.reviewStatus == .circled }
        let circledTakes = circled.map { Self.digestTake(from: $0, compositeOverride: $0.aiScores?.composite ?? 0) }

        let (completed, continued) = Self.sceneCoverage(from: dayClips)

        let dateString = Self.displayDateString(from: referenceDate)

        return DigestReport(
            projectName: projectName,
            date: dateString,
            totalClipsIngested: totalClipsIngested,
            totalDurationMinutes: totalDurationMinutes,
            averageCompositeScore: averageCompositeScore,
            topTakes: topTakes,
            flaggedTakes: flaggedTakes,
            circledTakes: circledTakes,
            scenesCompleted: completed,
            scenesContinued: continued
        )
    }

    public func sendDigest(_ report: DigestReport, to targets: [DeliveryTarget]) async {
        await NotificationService.shared.deliverDigest(report: report, targets: targets)
    }

    // MARK: - Private

    private func runScheduledDigest(projectId: String, clipStore: GRDBClipStore) async {
        let project = await clipStore.project(byId: projectId)
        guard let project, project.dailyDigestEnabled, !project.digestTargets.isEmpty else {
            return
        }

        let todayKey = Self.calendarDayKey(from: Date())
        if UserDefaults.standard.string(forKey: Self.lastSentKeyPrefix + projectId) == todayKey {
            return
        }

        let clips = await clipStore.fetchAllClips(forProjectId: projectId)
        let report = generateDigest(for: projectId, clips: clips, projectName: project.name, referenceDate: Date())
        await sendDigest(report, to: project.digestTargets)
        UserDefaults.standard.set(todayKey, forKey: Self.lastSentKeyPrefix + projectId)
    }

    private static func isFlaggedTake(_ clip: Clip) -> Bool {
        guard let s = clip.aiScores else { return false }
        return s.composite < 40 || s.audio < 30
    }

    private static func digestTake(from clip: Clip, compositeOverride: Double) -> DigestTake {
        let reason = clip.aiScores?.reasoning.first?.message ?? ""
        return DigestTake(
            clipId: clip.id,
            label: label(for: clip),
            compositeScore: compositeOverride,
            reasonSummary: reason,
            proxyThumbnailURL: clip.proxyR2URL
        )
    }

    private static func label(for clip: Clip) -> String {
        if let n = clip.narrativeMeta {
            let cam = clip.cameraAngle.map { " — \($0.uppercased())-CAM" } ?? ""
            return "SC: \(n.sceneNumber) / SH: \(n.shotCode) / TK: \(n.takeNumber)\(cam)"
        }
        if let d = clip.documentaryMeta {
            return "\(d.subjectName) — \(d.sessionLabel)"
        }
        return URL(fileURLWithPath: clip.sourcePath).lastPathComponent
    }

    private static func sceneCoverage(from clips: [Clip]) -> ([String], [String]) {
        var scenesWithClips = Set<String>()
        var scenesWithCircle = Set<String>()

        for clip in clips {
            if let scene = clip.narrativeMeta?.sceneNumber, !scene.isEmpty {
                scenesWithClips.insert(scene)
                if clip.reviewStatus == .circled {
                    scenesWithCircle.insert(scene)
                }
            }
        }

        let completed = scenesWithCircle.sorted()
        let continued = scenesWithClips.subtracting(scenesWithCircle).sorted()
        return (completed, continued)
    }

    private static func isIngestedOnSameCalendarDay(_ ingestedAt: String, as reference: Date) -> Bool {
        let ingested = parseIngestDate(ingestedAt) ?? Date.distantPast
        return Calendar.current.isDate(ingested, inSameDayAs: reference)
    }

    private static func parseIngestDate(_ raw: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func displayDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: date)
    }

    private static func calendarDayKey(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func secondsUntilNextLocalHour(_ hour: Int, minute: Int) -> TimeInterval {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard var target = cal.date(from: comps) else {
            return 24 * 3600
        }
        if target <= now {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(24 * 3600)
        }
        return target.timeIntervalSince(now)
    }
}
