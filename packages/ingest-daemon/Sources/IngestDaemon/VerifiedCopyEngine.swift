import CryptoKit
import Foundation

enum VerifiedCopyError: Error, LocalizedError {
    case unreadableSource(String)
    case unwritableDestination(String)
    case copyFailed(String)
    case verificationFailed(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource(let path):
            return "Unable to read source file: \(path)"
        case .unwritableDestination(let path):
            return "Unable to write destination file: \(path)"
        case .copyFailed(let message):
            return "Verified copy failed: \(message)"
        case .verificationFailed(let expected, let actual):
            return "Hash verification failed. expected=\(expected) actual=\(actual)"
        }
    }
}

enum HashAlgorithm: String, Codable, Sendable {
    case sha256
    case xxh64
}

struct OffloadVerificationResult: Codable, Sendable {
    let sourcePath: String
    let destinationPath: String
    let algorithm: HashAlgorithm
    let sourceHash: String
    let destinationHash: String
    let bytesCopied: Int64
    let verifiedAt: String
    let manifestPath: String?

    var isVerified: Bool {
        sourceHash == destinationHash
    }
}

enum VerifiedCopyEngine {
    private static let chunkSize = 1_048_576

    static func copyAndVerify(from sourceURL: URL, to destinationURL: URL) throws -> OffloadVerificationResult {
        let fileManager = FileManager.default
        let destinationDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        guard let input = InputStream(url: sourceURL) else {
            throw VerifiedCopyError.unreadableSource(sourceURL.path)
        }
        guard let output = OutputStream(url: destinationURL, append: false) else {
            throw VerifiedCopyError.unwritableDestination(destinationURL.path)
        }

        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        var sourceHasher = XXH64Hasher()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var bytesCopied: Int64 = 0

        while input.hasBytesAvailable {
            let bytesRead = input.read(&buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                throw input.streamError ?? VerifiedCopyError.copyFailed("unknown read error")
            }
            if bytesRead == 0 {
                break
            }

            let chunk = Data(buffer.prefix(bytesRead))
            sourceHasher.update(chunk)
            try writeAll(chunk, to: output)
            bytesCopied += Int64(bytesRead)
        }

        let sourceHash = sourceHasher.finalizeHex()
        let destinationHash = try hashFileXXH64(at: destinationURL)
        guard sourceHash == destinationHash else {
            throw VerifiedCopyError.verificationFailed(expected: sourceHash, actual: destinationHash)
        }

        return OffloadVerificationResult(
            sourcePath: sourceURL.path,
            destinationPath: destinationURL.path,
            algorithm: .xxh64,
            sourceHash: sourceHash,
            destinationHash: destinationHash,
            bytesCopied: bytesCopied,
            verifiedAt: ISO8601DateFormatter().string(from: Date()),
            manifestPath: nil
        )
    }

    static func hashFileSHA256(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw VerifiedCopyError.unreadableSource(url.path)
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                throw stream.streamError ?? VerifiedCopyError.copyFailed("sha256 read failure")
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(data: Data(buffer.prefix(bytesRead)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashFileXXH64(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw VerifiedCopyError.unreadableSource(url.path)
        }
        stream.open()
        defer { stream.close() }

        var hasher = XXH64Hasher()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                throw stream.streamError ?? VerifiedCopyError.copyFailed("xxh64 read failure")
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(Data(buffer.prefix(bytesRead)))
        }
        return hasher.finalizeHex()
    }

    private static func writeAll(_ data: Data, to stream: OutputStream) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            var offset = 0
            while offset < data.count {
                let written = stream.write(baseAddress + offset, maxLength: data.count - offset)
                if written <= 0 {
                    throw stream.streamError ?? VerifiedCopyError.copyFailed("write failed")
                }
                offset += written
            }
        }
    }
}

enum MHLManifestWriter {
    static func write(
        for result: OffloadVerificationResult,
        sourceURL: URL,
        destinationURL: URL,
        historyRootURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let ascmhlDirectory = historyRootURL.appendingPathComponent("ascmhl", isDirectory: true)
        try fileManager.createDirectory(at: ascmhlDirectory, withIntermediateDirectories: true)

        let chainURL = ascmhlDirectory.appendingPathComponent("ascmhl_chain.xml")
        let existingEntries = (try? readChainEntries(from: chainURL)) ?? []
        let nextSequenceNumber = (existingEntries.map { $0.sequenceNumber }.max() ?? 0) + 1

        let volumeLabel = sanitizeLabel(historyRootURL.lastPathComponent)
        let timestamp = manifestTimestamp(Date())
        let manifestName = String(format: "%04d_%@_%@.mhl", nextSequenceNumber, volumeLabel, timestamp)
        let manifestURL = ascmhlDirectory.appendingPathComponent(manifestName)

        let host = ProcessInfo.processInfo.hostName
        let creationDate = iso8601(result.verifiedAt)
        let relativePath = relativePath(from: historyRootURL, to: destinationURL)
        let size = result.bytesCopied
        let destinationModified = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.modificationDate] as? Date) ?? Date()
        let destinationModifiedISO = ISO8601DateFormatter().string(from: destinationModified)
        let md5 = try hashFileMD5(at: destinationURL)
        let c4 = try hashFileC4(at: destinationURL)
        let rootHashes = try computeRootDirectoryHashes(relativeFilePath: relativePath, fileHashXXH64: result.destinationHash)

        let directoryHashXML: String = {
            guard !rootHashes.directoryEntries.isEmpty else {
                return ""
            }
            let rendered = rootHashes.directoryEntries.map { entry in
                """
                    <directoryhash>
                      <path>\(escape(entry.path))</path>
                      <content>
                        <xxh64>\(entry.contentHashXXH64)</xxh64>
                      </content>
                      <structure>
                        <xxh64>\(entry.structureHashXXH64)</xxh64>
                      </structure>
                    </directoryhash>
                """
            }.joined(separator: "\n")
            return rendered + "\n"
        }()
        let childReferences = (try? listChildHistoryReferences(
            historyRootURL: historyRootURL,
            excludingChainURL: chainURL
        )) ?? []
        let referencesXML: String = {
            guard !childReferences.isEmpty else {
                return ""
            }
            let entries = childReferences.map { reference in
                """
                  <hashlistreference>
                    <path>\(escape(reference.path))</path>
                    <c4>\(escape(reference.c4))</c4>
                  </hashlistreference>
                """
            }.joined(separator: "\n")
            return "  <references>\n\(entries)\n  </references>\n"
        }()

        // Emit ASC MHL v2-compatible shape for broad tool interoperability.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="2.0"
          xmlns="urn:ASC:MHL:v2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="urn:ASC:MHL:v2.0 ASCMHL.xsd">
          <creatorinfo>
            <creationdate>\(creationDate)</creationdate>
            <hostname>\(escape(host))</hostname>
            <tool version="1.0">SLATE IngestDaemon</tool>
          </creatorinfo>
          <processinfo>
            <process>transfer</process>
            <roothash>
              <content>
                <xxh64>\(rootHashes.contentHashXXH64)</xxh64>
              </content>
              <structure>
                <xxh64>\(rootHashes.structureHashXXH64)</xxh64>
              </structure>
            </roothash>
          </processinfo>
          <hashes>
            <hash>
              <path size="\(size)" lastmodificationdate="\(destinationModifiedISO)">\(escape(relativePath))</path>
              <c4 action="verified" hashdate="\(creationDate)">\(c4)</c4>
              <md5 action="verified" hashdate="\(creationDate)">\(md5)</md5>
              <xxh64 action="verified" hashdate="\(creationDate)">\(result.destinationHash)</xxh64>
              <metadata>
                <source_path>\(escape(result.sourcePath))</source_path>
                <destination_path>\(escape(result.destinationPath))</destination_path>
              </metadata>
            </hash>
        \(directoryHashXML)  </hashes>
        \(referencesXML)
        </hashlist>
        """
        try xml.write(to: manifestURL, atomically: true, encoding: .utf8)

        // ASC MHL chain references use c4 per schema.
        let generationFingerprint = try hashFileC4(at: manifestURL)
        let updatedEntries = existingEntries + [.init(
            sequenceNumber: nextSequenceNumber,
            path: manifestName,
            c4: generationFingerprint
        )]
        let chainXML = renderChainXML(entries: updatedEntries)
        try chainXML.write(to: chainURL, atomically: true, encoding: String.Encoding.utf8)

        return manifestURL
    }

    private static func iso8601(_ fallbackString: String) -> String {
        if let date = ISO8601DateFormatter().date(from: fallbackString) {
            return ISO8601DateFormatter().string(from: date)
        }
        return ISO8601DateFormatter().string(from: Date())
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private struct ChainEntry {
        let sequenceNumber: Int
        let path: String
        let c4: String
    }

    private struct RootDirectoryHashes {
        let contentHashXXH64: String
        let structureHashXXH64: String
        let directoryEntries: [DirectoryEntry]
    }

    private struct HashListReference {
        let path: String
        let c4: String
    }

    private struct DirectoryEntry {
        let path: String
        let contentHashXXH64: String
        let structureHashXXH64: String
    }

    private static func sanitizeLabel(_ value: String) -> String {
        let upper = value.uppercased()
        let filtered = upper.map { ch -> Character in
            if ch.isLetter || ch.isNumber {
                return ch
            }
            return "_"
        }
        let collapsed = String(filtered).replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "SLATE" : String(trimmed.prefix(24))
    }

    private static func manifestTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }

    private static func relativePath(from rootURL: URL, to fileURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    private static func hashFileMD5(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw VerifiedCopyError.unreadableSource(url.path)
        }
        stream.open()
        defer { stream.close() }

        var hasher = Insecure.MD5()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw stream.streamError ?? VerifiedCopyError.copyFailed("md5 read failure")
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(data: Data(buffer.prefix(bytesRead)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hashFileC4(at url: URL) throws -> String {
        guard let stream = InputStream(url: url) else {
            throw VerifiedCopyError.unreadableSource(url.path)
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA512()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw stream.streamError ?? VerifiedCopyError.copyFailed("c4 read failure")
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(data: Data(buffer.prefix(bytesRead)))
        }
        let digest = Array(hasher.finalize())
        return c4String(fromSHA512Digest: digest)
    }

    private static func c4String(fromSHA512Digest digest: [UInt8]) -> String {
        let charset = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        let base = 58
        let c4Length = 90
        let zeroSymbol = "1"

        var number = digest
        var encoded = ""
        while !number.isEmpty && !number.allSatisfy({ $0 == 0 }) {
            var quotient: [UInt8] = []
            quotient.reserveCapacity(number.count)
            var remainder = 0
            var started = false
            for byte in number {
                let accumulator = remainder * 256 + Int(byte)
                let q = accumulator / base
                remainder = accumulator % base
                if q != 0 || started {
                    quotient.append(UInt8(q))
                    started = true
                }
            }
            encoded = String(charset[remainder]) + encoded
            number = quotient
        }

        let bodyLength = c4Length - 2
        if encoded.count < bodyLength {
            encoded = String(repeating: zeroSymbol, count: bodyLength - encoded.count) + encoded
        } else if encoded.count > bodyLength {
            encoded = String(encoded.suffix(bodyLength))
        }
        return "c4" + encoded
    }

    private static func computeRootDirectoryHashes(
        relativeFilePath: String,
        fileHashXXH64: String
    ) throws -> RootDirectoryHashes {
        struct DirectoryContext {
            var contentHashes: [String] = []
            var structureHashes: [String] = []
        }

        let normalizedPath = relativeFilePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathComponents = normalizedPath.split(separator: "/").map(String.init)
        guard let filename = pathComponents.last else {
            return .init(
                contentHashXXH64: fileHashXXH64,
                structureHashXXH64: fileHashXXH64,
                directoryEntries: []
            )
        }

        let directoryComponents = Array(pathComponents.dropLast())
        var allDirectoryPaths: [String] = [""]
        if !directoryComponents.isEmpty {
            var current = ""
            for component in directoryComponents {
                current = current.isEmpty ? component : "\(current)/\(component)"
                allDirectoryPaths.append(current)
            }
        }

        var contexts: [String: DirectoryContext] = Dictionary(uniqueKeysWithValues: allDirectoryPaths.map { ($0, DirectoryContext()) })
        let leafDirectoryPath = directoryComponents.joined(separator: "/")
        contexts[leafDirectoryPath, default: DirectoryContext()].contentHashes.append(fileHashXXH64)
        let fileStructureSeed = Data(filename.utf8) + (try decodeHex(fileHashXXH64))
        contexts[leafDirectoryPath, default: DirectoryContext()].structureHashes.append(hashDataXXH64(fileStructureSeed))

        let sortedByDepth = allDirectoryPaths.sorted { lhs, rhs in
            lhs.split(separator: "/").count > rhs.split(separator: "/").count
        }

        var computed: [String: (content: String, structure: String)] = [:]
        for path in sortedByDepth {
            let context = contexts[path, default: DirectoryContext()]
            let content = try hashOfHashListXXH64(context.contentHashes)
            let structure = try hashOfHashListXXH64(context.structureHashes)
            computed[path] = (content, structure)

            guard !path.isEmpty else { continue }
            let basename = path.split(separator: "/").last.map(String.init) ?? path
            var parentPath = ""
            if let slash = path.lastIndex(of: "/") {
                parentPath = String(path[..<slash])
            }
            contexts[parentPath, default: DirectoryContext()].contentHashes.append(content)
            let structureSeed = Data(basename.utf8) + (try decodeHex(structure))
            contexts[parentPath, default: DirectoryContext()].structureHashes.append(hashDataXXH64(structureSeed))
        }

        let root = computed[""] ?? (fileHashXXH64, fileHashXXH64)
        let entries = computed
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
            .map { key, value in
                DirectoryEntry(
                    path: key.hasSuffix("/") ? key : key + "/",
                    contentHashXXH64: value.content,
                    structureHashXXH64: value.structure
                )
            }

        return RootDirectoryHashes(
            contentHashXXH64: root.content,
            structureHashXXH64: root.structure,
            directoryEntries: entries
        )
    }

    private static func hashDataXXH64(_ data: Data) -> String {
        var hasher = XXH64Hasher()
        hasher.update(data)
        return hasher.finalizeHex()
    }

    private static func hashOfHashListXXH64(_ hashStrings: [String]) throws -> String {
        var hasher = XXH64Hasher()
        if hashStrings.isEmpty {
            return hasher.finalizeHex()
        }
        for hash in hashStrings.sorted() {
            hasher.update(try decodeHex(hash))
        }
        return hasher.finalizeHex()
    }

    private static func decodeHex(_ value: String) throws -> Data {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleaned.count.isMultiple(of: 2) else {
            throw VerifiedCopyError.copyFailed("invalid hex string length")
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let chunk = cleaned[index..<next]
            guard let byte = UInt8(chunk, radix: 16) else {
                throw VerifiedCopyError.copyFailed("invalid hex string value")
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private static func readChainEntries(from chainURL: URL) throws -> [ChainEntry] {
        guard FileManager.default.fileExists(atPath: chainURL.path) else {
            return []
        }
        let xml = try String(contentsOf: chainURL, encoding: .utf8)
        let pattern = #"<hashlist\s+sequencenr="(\d+)">\s*<path>([^<]+)</path>\s*<c4>([^<]+)</c4>\s*</hashlist>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)
        var entries: [ChainEntry] = []
        for match in matches {
            guard
                let seqRange = Range(match.range(at: 1), in: xml),
                let pathRange = Range(match.range(at: 2), in: xml),
                let c4Range = Range(match.range(at: 3), in: xml),
                let sequenceNumber = Int(xml[seqRange])
            else {
                continue
            }
            entries.append(.init(
                sequenceNumber: sequenceNumber,
                path: String(xml[pathRange]),
                c4: String(xml[c4Range])
            ))
        }
        return entries.sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    private static func listChildHistoryReferences(
        historyRootURL: URL,
        excludingChainURL: URL
    ) throws -> [HashListReference] {
        let fileManager = FileManager.default
        let rootPath = historyRootURL.standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: historyRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return []
        }

        var references: [HashListReference] = []
        for case let fileURL as URL in enumerator {
            let standardized = fileURL.standardizedFileURL
            if standardized.path == excludingChainURL.standardizedFileURL.path {
                continue
            }
            if standardized.lastPathComponent != "ascmhl_chain.xml" {
                continue
            }
            let components = standardized.pathComponents
            if !components.contains("ascmhl") {
                continue
            }
            let entries = try readChainEntries(from: standardized)
            guard let latest = entries.max(by: { $0.sequenceNumber < $1.sequenceNumber }) else {
                continue
            }
            let manifestURL = standardized.deletingLastPathComponent().appendingPathComponent(latest.path)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }
            let relative = relativePath(from: historyRootURL, to: manifestURL)
            if !relative.isEmpty && manifestURL.path.hasPrefix(rootPath) {
                references.append(.init(path: relative, c4: latest.c4))
            }
        }

        return references.sorted { $0.path < $1.path }
    }

    private static func renderChainXML(entries: [ChainEntry]) -> String {
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<ascmhldirectory xmlns="urn:ASC:MHL:DIRECTORY:v2.0">"#)
        for entry in entries.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            lines.append(#"  <hashlist sequencenr="\#(entry.sequenceNumber)">"#)
            lines.append("    <path>\(escape(entry.path))</path>")
            lines.append("    <c4>\(escape(entry.c4))</c4>")
            lines.append("  </hashlist>")
        }
        lines.append("</ascmhldirectory>")
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Streaming XXH64

struct XXH64Hasher {
    private static let prime1: UInt64 = 11_400_714_785_074_694_791
    private static let prime2: UInt64 = 14_029_467_366_897_019_727
    private static let prime3: UInt64 = 1_609_587_929_392_839_161
    private static let prime4: UInt64 = 9_650_029_242_287_828_579
    private static let prime5: UInt64 = 2_870_177_450_012_600_261

    private let seed: UInt64
    private var totalLength: UInt64 = 0
    private var v1: UInt64
    private var v2: UInt64
    private var v3: UInt64
    private var v4: UInt64
    private var mem = [UInt8]()

    init(seed: UInt64 = 0) {
        self.seed = seed
        self.v1 = seed &+ XXH64Hasher.prime1 &+ XXH64Hasher.prime2
        self.v2 = seed &+ XXH64Hasher.prime2
        self.v3 = seed
        self.v4 = seed &- XXH64Hasher.prime1
        self.mem.reserveCapacity(32)
    }

    mutating func update(_ data: Data) {
        guard !data.isEmpty else { return }
        totalLength &+= UInt64(data.count)

        let bytes = [UInt8](data)
        var index = 0

        if mem.count + bytes.count < 32 {
            mem.append(contentsOf: bytes)
            return
        }

        if !mem.isEmpty {
            let fill = 32 - mem.count
            mem.append(contentsOf: bytes[0..<fill])
            processChunk32(mem, start: 0)
            mem.removeAll(keepingCapacity: true)
            index += fill
        }

        while index + 32 <= bytes.count {
            processChunk32(bytes, start: index)
            index += 32
        }

        if index < bytes.count {
            mem.append(contentsOf: bytes[index..<bytes.count])
        }
    }

    mutating func finalize() -> UInt64 {
        var hash: UInt64
        if totalLength >= 32 {
            hash = rotateLeft(v1, by: 1) &+ rotateLeft(v2, by: 7) &+ rotateLeft(v3, by: 12) &+ rotateLeft(v4, by: 18)
            hash = mergeRound(hash, v1)
            hash = mergeRound(hash, v2)
            hash = mergeRound(hash, v3)
            hash = mergeRound(hash, v4)
        } else {
            hash = seed &+ XXH64Hasher.prime5
        }

        hash &+= totalLength

        var index = 0
        while index + 8 <= mem.count {
            let lane = readUInt64LE(mem, at: index)
            let k1 = round(0, lane)
            hash ^= k1
            hash = rotateLeft(hash, by: 27) &* XXH64Hasher.prime1 &+ XXH64Hasher.prime4
            index += 8
        }

        if index + 4 <= mem.count {
            let lane = UInt64(readUInt32LE(mem, at: index))
            hash ^= lane &* XXH64Hasher.prime1
            hash = rotateLeft(hash, by: 23) &* XXH64Hasher.prime2 &+ XXH64Hasher.prime3
            index += 4
        }

        while index < mem.count {
            hash ^= UInt64(mem[index]) &* XXH64Hasher.prime5
            hash = rotateLeft(hash, by: 11) &* XXH64Hasher.prime1
            index += 1
        }

        hash ^= hash >> 33
        hash = hash &* XXH64Hasher.prime2
        hash ^= hash >> 29
        hash = hash &* XXH64Hasher.prime3
        hash ^= hash >> 32
        return hash
    }

    mutating func finalizeHex() -> String {
        let digest = finalize()
        return String(format: "%016llx", digest)
    }

    private mutating func processChunk32(_ bytes: [UInt8], start: Int) {
        v1 = round(v1, readUInt64LE(bytes, at: start))
        v2 = round(v2, readUInt64LE(bytes, at: start + 8))
        v3 = round(v3, readUInt64LE(bytes, at: start + 16))
        v4 = round(v4, readUInt64LE(bytes, at: start + 24))
    }

    private func round(_ acc: UInt64, _ lane: UInt64) -> UInt64 {
        var value = acc &+ (lane &* XXH64Hasher.prime2)
        value = rotateLeft(value, by: 31)
        value = value &* XXH64Hasher.prime1
        return value
    }

    private func mergeRound(_ acc: UInt64, _ value: UInt64) -> UInt64 {
        var merged = acc ^ round(0, value)
        merged = merged &* XXH64Hasher.prime1 &+ XXH64Hasher.prime4
        return merged
    }

    private func rotateLeft(_ value: UInt64, by shift: UInt64) -> UInt64 {
        (value << shift) | (value >> (64 - shift))
    }

    private func readUInt64LE(_ bytes: [UInt8], at index: Int) -> UInt64 {
        UInt64(bytes[index])
            | (UInt64(bytes[index + 1]) << 8)
            | (UInt64(bytes[index + 2]) << 16)
            | (UInt64(bytes[index + 3]) << 24)
            | (UInt64(bytes[index + 4]) << 32)
            | (UInt64(bytes[index + 5]) << 40)
            | (UInt64(bytes[index + 6]) << 48)
            | (UInt64(bytes[index + 7]) << 56)
    }

    private func readUInt32LE(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}
