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

    public init() {}

    /// Public HTTPS URL for the object (no trailing slash on base; key segments preserved).
    public func publicObjectURL(baseURL: String, key: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(trimmed)/\(trimmedKey)"
    }

    /// PUT object to R2 with AWS SigV4; returns the public URL for `key`.
    public func upload(localURL: URL, r2Key: String, contentType: String) async throws -> String {
        guard let credentials = R2Credentials.loadFromKeychain() else {
            throw R2UploaderError.missingCredentials
        }
        let body = try Data(contentsOf: localURL)
        let publicBase = credentials.publicBaseURL
        try await uploadWithRetry(
            credentials: credentials,
            body: body,
            r2Key: r2Key,
            contentType: contentType
        )
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

    private func performPut(
        credentials: R2Credentials,
        body: Data,
        r2Key: String,
        contentType: String
    ) async throws {
        let host = "\(credentials.accountId).r2.cloudflarestorage.com"
        let canonicalURI = pathStyleURI(bucket: credentials.bucketName, key: r2Key)
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
            "PUT",
            canonicalURI,
            "",
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

        guard let url = URL(string: "https://\(host)\(canonicalURI)") else {
            throw R2UploaderError.uploadFailed("Invalid R2 URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentLength, forHTTPHeaderField: "Content-Length")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw R2UploaderError.uploadFailed("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw R2UploaderError.uploadFailed("HTTP \(http.statusCode)")
        }
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
}

// MARK: - Errors

public enum R2UploaderError: Error, Sendable {
    case missingCredentials
    case uploadFailed(String)
    case thumbnailFailed(String)
}
