// SLATE — Cloudflare R2 uploads (S3-compatible, AWS Signature Version 4)
// Owned by: Claude Code

import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import Security
import UniformTypeIdentifiers

// MARK: - Credentials

public struct R2Credentials: Sendable {
    public let accountId: String
    public let accessKeyId: String
    public let secretAccessKey: String
    public let bucketName: String
    public let publicBaseURL: String

    public static func loadFromKeychain() -> R2Credentials? {
        func secret(service: String, account: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return value
        }

        guard
            let accountId = secret(service: "SLATE", account: "R2AccountId"),
            let accessKeyId = secret(service: "SLATE", account: "R2AccessKeyId"),
            let secretAccessKey = secret(service: "SLATE", account: "R2SecretAccessKey"),
            let bucketName = secret(service: "SLATE", account: "R2BucketName"),
            let publicBaseURL = secret(service: "SLATE", account: "R2PublicBaseURL")
        else {
            return nil
        }

        return R2Credentials(
            accountId: accountId,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            bucketName: bucketName,
            publicBaseURL: publicBaseURL
        )
    }
}

// MARK: - R2 Uploader

public actor R2Uploader {
    private let region = "auto"
    private let service = "s3"
    private let multipartThresholdBytes = 16 * 1024 * 1024
    private let multipartChunkSizeBytes = 8 * 1024 * 1024
    private let stateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("slate-r2-upload-state", isDirectory: true)

    private struct MultipartUploadState: Codable, Sendable {
        var uploadId: String
        var key: String
        var fileSize: Int64
        var fileModifiedAt: TimeInterval
        var contentType: String
        var completedParts: [Int: String]
    }

    public init() {}

    /// Public HTTPS URL for the object (no trailing slash on base; key segments preserved).
    public func publicObjectURL(baseURL: String, key: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(trimmed)/\(trimmedKey)"
    }

    /// PUT object to R2 with AWS SigV4; returns the public URL for `key`.
    public func upload(
        localURL: URL,
        r2Key: String,
        contentType: String,
        throttleBytesPerSecond: Int? = nil
    ) async throws -> String {
        guard let credentials = R2Credentials.loadFromKeychain() else {
            throw R2UploaderError.missingCredentials
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0
        let fileModifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let publicBase = credentials.publicBaseURL

        if fileSize >= Int64(multipartThresholdBytes) {
            try await multipartUpload(
                credentials: credentials,
                localURL: localURL,
                fileSize: fileSize,
                fileModifiedAt: fileModifiedAt,
                r2Key: r2Key,
                contentType: contentType,
                throttleBytesPerSecond: throttleBytesPerSecond
            )
        } else {
            let body = try Data(contentsOf: localURL)
            try await uploadWithRetry(
                credentials: credentials,
                body: body,
                r2Key: r2Key,
                contentType: contentType
            )
        }
        return publicObjectURL(baseURL: publicBase, key: r2Key)
    }

    /// Extract a JPEG thumbnail at ~10% of duration (saved to a temp file; caller may delete).
    public func generateThumbnail(proxyURL: URL) async throws -> URL {
        let asset = AVAsset(url: proxyURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw R2UploaderError.thumbnailFailed("Invalid proxy duration")
        }
        let time = CMTime(seconds: seconds * 0.1, preferredTimescale: 600)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var actualTime = CMTime.zero
        let cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-proxy-thumb-\(UUID().uuidString).jpg")
        try writeJPEG(cgImage, to: tempURL, quality: 0.85)
        return tempURL
    }

    // MARK: - Internals

    private func uploadWithRetry(
        credentials: R2Credentials,
        body: Data,
        r2Key: String,
        contentType: String
    ) async throws {
        var lastError: Error = R2UploaderError.uploadFailed("Unknown error")
        var delayNanoseconds: UInt64 = 1_000_000_000

        for attempt in 0..<3 {
            do {
                try await performPut(
                    credentials: credentials,
                    body: body,
                    r2Key: r2Key,
                    contentType: contentType
                )
                return
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    delayNanoseconds *= 2
                }
            }
        }
        throw lastError
    }

    private func multipartUpload(
        credentials: R2Credentials,
        localURL: URL,
        fileSize: Int64,
        fileModifiedAt: TimeInterval,
        r2Key: String,
        contentType: String,
        throttleBytesPerSecond: Int?
    ) async throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let stateURL = stateURLForUpload(fileURL: localURL, key: r2Key)

        var state = try loadMultipartState(from: stateURL)
        if let existing = state,
           (existing.fileSize != fileSize || existing.fileModifiedAt != fileModifiedAt || existing.contentType != contentType || existing.key != r2Key) {
            state = nil
            try? FileManager.default.removeItem(at: stateURL)
        }

        if state == nil {
            let uploadId = try await initiateMultipartUpload(
                credentials: credentials,
                r2Key: r2Key,
                contentType: contentType
            )
            state = MultipartUploadState(
                uploadId: uploadId,
                key: r2Key,
                fileSize: fileSize,
                fileModifiedAt: fileModifiedAt,
                contentType: contentType,
                completedParts: [:]
            )
            try saveMultipartState(state!, to: stateURL)
        }

        guard var activeState = state else {
            throw R2UploaderError.uploadFailed("Missing multipart upload state")
        }

        let totalParts = max(1, Int((fileSize + Int64(multipartChunkSizeBytes) - 1) / Int64(multipartChunkSizeBytes)))
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }

        for partNumber in 1...totalParts {
            if activeState.completedParts[partNumber] != nil {
                continue
            }
            let offset = Int64(partNumber - 1) * Int64(multipartChunkSizeBytes)
            let remaining = fileSize - offset
            let bytesToRead = Int(min(Int64(multipartChunkSizeBytes), max(remaining, 0)))
            try handle.seek(toOffset: UInt64(offset))
            let chunk = try handle.read(upToCount: bytesToRead) ?? Data()
            guard !chunk.isEmpty else {
                throw R2UploaderError.uploadFailed("Failed to read upload chunk \(partNumber)")
            }

            let etag = try await uploadPartWithRetry(
                credentials: credentials,
                r2Key: r2Key,
                contentType: contentType,
                uploadId: activeState.uploadId,
                partNumber: partNumber,
                body: chunk
            )

            activeState.completedParts[partNumber] = etag
            try saveMultipartState(activeState, to: stateURL)
            try await throttleAfterUpload(byteCount: chunk.count, throttleOverride: throttleBytesPerSecond)
        }

        try await completeMultipartUpload(
            credentials: credentials,
            r2Key: r2Key,
            uploadId: activeState.uploadId,
            parts: activeState.completedParts
        )
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func uploadPartWithRetry(
        credentials: R2Credentials,
        r2Key: String,
        contentType: String,
        uploadId: String,
        partNumber: Int,
        body: Data
    ) async throws -> String {
        var lastError: Error = R2UploaderError.uploadFailed("Unknown multipart error")
        var delayNanoseconds: UInt64 = 1_000_000_000

        for attempt in 0..<8 {
            do {
                return try await uploadPart(
                    credentials: credentials,
                    r2Key: r2Key,
                    contentType: contentType,
                    uploadId: uploadId,
                    partNumber: partNumber,
                    body: body
                )
            } catch {
                lastError = error
                if attempt < 7 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    // If we're offline, back off more aggressively and keep state for seamless resume.
                    if isConnectivityError(error) {
                        delayNanoseconds = min(delayNanoseconds * 2, 30_000_000_000)
                    } else {
                        delayNanoseconds = min(delayNanoseconds * 2, 8_000_000_000)
                    }
                }
            }
        }
        throw lastError
    }

    private func uploadPart(
        credentials: R2Credentials,
        r2Key: String,
        contentType: String,
        uploadId: String,
        partNumber: Int,
        body: Data
    ) async throws -> String {
        let response = try await performSignedRequest(
            credentials: credentials,
            method: "PUT",
            r2Key: r2Key,
            query: [
                URLQueryItem(name: "partNumber", value: "\(partNumber)"),
                URLQueryItem(name: "uploadId", value: uploadId)
            ],
            contentType: contentType,
            body: body
        )
        return normalizedETag(response.http.value(forHTTPHeaderField: "ETag"))
    }

    private func initiateMultipartUpload(
        credentials: R2Credentials,
        r2Key: String,
        contentType: String
    ) async throws -> String {
        let response = try await performSignedRequest(
            credentials: credentials,
            method: "POST",
            r2Key: r2Key,
            query: [URLQueryItem(name: "uploads", value: "")],
            contentType: contentType,
            body: Data()
        )
        guard let uploadId = extractXMLTag("UploadId", from: response.data) else {
            throw R2UploaderError.uploadFailed("Multipart init response missing UploadId")
        }
        return uploadId
    }

    private func completeMultipartUpload(
        credentials: R2Credentials,
        r2Key: String,
        uploadId: String,
        parts: [Int: String]
    ) async throws {
        let xmlParts = parts.keys.sorted().compactMap { partNumber -> String? in
            guard let etag = parts[partNumber] else { return nil }
            return "<Part><PartNumber>\(partNumber)</PartNumber><ETag>\"\(etag)\"</ETag></Part>"
        }.joined()
        let body = Data("<CompleteMultipartUpload>\(xmlParts)</CompleteMultipartUpload>".utf8)
        _ = try await performSignedRequest(
            credentials: credentials,
            method: "POST",
            r2Key: r2Key,
            query: [URLQueryItem(name: "uploadId", value: uploadId)],
            contentType: "application/xml",
            body: body
        )
    }

    private func performPut(
        credentials: R2Credentials,
        body: Data,
        r2Key: String,
        contentType: String
    ) async throws {
        _ = try await performSignedRequest(
            credentials: credentials,
            method: "PUT",
            r2Key: r2Key,
            query: [],
            contentType: contentType,
            body: body
        )
    }

    private func performSignedRequest(
        credentials: R2Credentials,
        method: String,
        r2Key: String,
        query: [URLQueryItem],
        contentType: String,
        body: Data
    ) async throws -> (data: Data, http: HTTPURLResponse) {
        let host = "\(credentials.accountId).r2.cloudflarestorage.com"
        let canonicalURI = pathStyleURI(bucket: credentials.bucketName, key: r2Key)
        let canonicalQuery = canonicalQueryString(query)
        let requestQuery = requestQueryString(query)
        let payloadHash = sha256Hex(body)

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let contentLength = "\(body.count)"

        let signedHeaders = "content-length;content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalHeaders = [
            "content-length:\(contentLength)",
            "content-type:\(contentType)",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let hashedCanonicalRequest = sha256Hex(Data(canonicalRequest.utf8))

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            hashedCanonicalRequest
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretKey: credentials.secretAccessKey, dateStamp: dateStamp, region: region, service: service)
        let signatureData = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
        let signature = signatureData.map { String(format: "%02x", $0) }.joined()

        let authorization =
            "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        let querySuffix = requestQuery.isEmpty ? "" : "?\(requestQuery)"
        guard let url = URL(string: "https://\(host)\(canonicalURI)\(querySuffix)") else {
            throw R2UploaderError.uploadFailed("Invalid R2 URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentLength, forHTTPHeaderField: "Content-Length")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw R2UploaderError.uploadFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw R2UploaderError.uploadFailed("HTTP \(http.statusCode)")
        }
        return (responseData, http)
    }

    private func canonicalQueryString(_ query: [URLQueryItem]) -> String {
        guard !query.isEmpty else { return "" }
        let encoded = query.map { (item: URLQueryItem) -> (String, String) in
            let name = awsEncodePathSegment(item.name)
            let value = awsEncodePathSegment(item.value ?? "")
            return (name, value)
        }.sorted { lhs, rhs in
            if lhs.0 == rhs.0 {
                return lhs.1 < rhs.1
            }
            return lhs.0 < rhs.0
        }
        return encoded.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private func requestQueryString(_ query: [URLQueryItem]) -> String {
        guard !query.isEmpty else { return "" }
        return query.map { item in
            let name = awsEncodePathSegment(item.name)
            let value = awsEncodePathSegment(item.value ?? "")
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }

    private func pathStyleURI(bucket: String, key: String) -> String {
        let encodedBucket = awsEncodePathSegment(bucket)
        let encodedKey = key.split(separator: "/").map { awsEncodePathSegment(String($0)) }.joined(separator: "/")
        return "/\(encodedBucket)/\(encodedKey)"
    }

    private func awsEncodePathSegment(_ s: String) -> String {
        var result = ""
        for byte in s.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                result.append(Character(UnicodeScalar(byte)))
            default:
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    private func deriveSigningKey(secretKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kSecret = Data("AWS4\(secretKey)".utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        return hmacSHA256(key: kService, data: Data("aws4_request".utf8))
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw R2UploaderError.thumbnailFailed("Could not create JPEG destination")
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw R2UploaderError.thumbnailFailed("Could not finalize JPEG")
        }
    }

    private func stateURLForUpload(fileURL: URL, key: String) -> URL {
        let fingerprint = sha256Hex(Data("\(fileURL.path)::\(key)".utf8))
        return stateDirectory.appendingPathComponent("\(fingerprint).json")
    }

    private func loadMultipartState(from url: URL) throws -> MultipartUploadState? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MultipartUploadState.self, from: data)
    }

    private func saveMultipartState(_ state: MultipartUploadState, to url: URL) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    private func normalizedETag(_ raw: String?) -> String {
        (raw ?? "").replacingOccurrences(of: "\"", with: "")
    }

    private func extractXMLTag(_ tag: String, from data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let startRange = xml.range(of: open), let endRange = xml.range(of: close) else {
            return nil
        }
        return String(xml[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func throttleAfterUpload(byteCount: Int, throttleOverride: Int?) async throws {
        let bytesPerSecond = throttleOverride ?? uploadThrottleBytesPerSecond()
        guard let bytesPerSecond, bytesPerSecond > 0 else {
            return
        }
        let sleepSeconds = Double(byteCount) / Double(bytesPerSecond)
        let nanos = UInt64(max(0, sleepSeconds) * 1_000_000_000)
        if nanos > 0 {
            try await Task.sleep(nanoseconds: nanos)
        }
    }

    private func uploadThrottleBytesPerSecond() -> Int? {
        let env = ProcessInfo.processInfo.environment["SLATE_UPLOAD_THROTTLE_BPS"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, let value = Int(env), value > 0 {
            return value
        }
        let defaultsValue = UserDefaults.standard.integer(forKey: "SLATE.uploadThrottleBytesPerSecond")
        return defaultsValue > 0 ? defaultsValue : nil
    }

    private func isConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - Errors

public enum R2UploaderError: Error, Sendable {
    case missingCredentials
    case uploadFailed(String)
    case thumbnailFailed(String)
}
