import CryptoKit
import Foundation

struct RuntimeConfiguration: Equatable, Sendable {
    static let productionHost = "whtejsviizgejauasqqt.supabase.co"
    let supabaseURL: URL
    let supabasePublishableKey: String

    var backendFingerprint: String {
        let digest = SHA256.hash(data: Data(supabaseURL.absoluteString.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func resolve(
        releaseChannel: AppReleaseChannel = .resolve(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> Self {
        if releaseChannel == .appStore {
            return Self(
                supabaseURL: URL(string: "https://\(productionHost)")!,
                supabasePublishableKey: "sb_publishable_kkASOI4rRTX8Drob21hkCw_VwUex63Y"
            )
        }

        let environmentURL = environment["SIDEY_SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentKey = environment["SIDEY_SUPABASE_PUBLISHABLE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundledURL = (bundleInfo["SIDEYSupabaseURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundledKey = (bundleInfo["SIDEYSupabasePublishableKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if environmentURL != nil || environmentKey != nil {
            guard let rawURL = environmentURL, !rawURL.isEmpty,
                  let key = environmentKey, !key.isEmpty,
                  let url = URL(string: rawURL), Self.isAllowedBackendURL(url)
            else { throw RuntimeConfigurationError.incompleteEnvironment }
            guard !Self.looksLikeSecretKey(key) else { throw RuntimeConfigurationError.secretKeyNotAllowed }
            guard url.host?.lowercased() != Self.productionHost else {
                throw RuntimeConfigurationError.productionBackendNotAllowedInDevelopment
            }
            return Self(supabaseURL: url, supabasePublishableKey: key)
        }

        guard let rawURL = bundledURL, !rawURL.isEmpty,
              let key = bundledKey, !key.isEmpty,
              let url = URL(string: rawURL), Self.isAllowedBackendURL(url)
        else { throw RuntimeConfigurationError.missingDevelopmentConfiguration }
        guard !Self.looksLikeSecretKey(key) else { throw RuntimeConfigurationError.secretKeyNotAllowed }
        guard url.host?.lowercased() != Self.productionHost else {
            throw RuntimeConfigurationError.productionBackendNotAllowedInDevelopment
        }
        return Self(supabaseURL: url, supabasePublishableKey: key)
    }

    var isProductionBackend: Bool {
        supabaseURL.host?.lowercased() == Self.productionHost
    }

    private static func isAllowedBackendURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private static func looksLikeSecretKey(_ value: String) -> Bool {
        if value.hasPrefix("sb_secret_") || value.hasPrefix("service_role") {
            return true
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var encodedPayload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encodedPayload += String(repeating: "=", count: (4 - encodedPayload.count % 4) % 4)
        guard let data = Data(base64Encoded: encodedPayload),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return payload["role"] as? String == "service_role"
    }
}

enum RuntimeConfigurationError: LocalizedError, Equatable {
    case incompleteEnvironment
    case secretKeyNotAllowed
    case missingDevelopmentConfiguration
    case productionBackendNotAllowedInDevelopment

    var errorDescription: String? {
        switch self {
        case .incompleteEnvironment:
            "SIDEY_SUPABASE_URL과 SIDEY_SUPABASE_PUBLISHABLE_KEY를 모두 설정해야 합니다."
        case .secretKeyNotAllowed:
            "클라이언트에 Supabase secret/service-role 키를 사용할 수 없습니다."
        case .missingDevelopmentConfiguration:
            "Sidey-dev에는 SIDEY-staging URL과 publishable key가 필요합니다."
        case .productionBackendNotAllowedInDevelopment:
            "Sidey-dev는 production Supabase 프로젝트에 연결할 수 없습니다."
        }
    }
}
