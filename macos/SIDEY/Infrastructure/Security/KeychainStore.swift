import Foundation
import LocalAuthentication
import Security
import Supabase

protocol KeychainSecurityPerforming: Sendable {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?)
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private struct SystemKeychainSecurity: KeychainSecurityPerforming {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        return (status, result as? Data)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

/// 한 번의 앱 실행에서 Keychain 인증 상태와 읽기 결과를 공유한다.
///
/// Supabase Auth가 부팅 중 같은 키를 여러 번 조회하더라도 실제 Security API는
/// 한 번만 호출한다. 사용자가 인증을 거부하면 이후 요청은 시스템 창을 다시
/// 띄우지 않고 즉시 같은 오류를 반환한다.
final class KeychainAccessSession: @unchecked Sendable {
    static let shared = KeychainAccessSession()

    private struct CacheKey: Hashable {
        let service: String
        let account: String
    }

    private enum CachedValue {
        case missing
        case data(Data)
    }

    private let lock = NSLock()
    private let security: any KeychainSecurityPerforming
    private let authenticationContext: LAContext
    private var cache: [CacheKey: CachedValue] = [:]
    private var deniedStatus: OSStatus?
    private var accessDeniedHandler: (@Sendable (OSStatus) -> Void)?
    private var didNotifyAccessDenied = false

    init(
        operationReason: String = KeychainStore.defaultOperationReason,
        security: any KeychainSecurityPerforming = SystemKeychainSecurity(),
        authenticationContext: LAContext = LAContext()
    ) {
        self.security = security
        self.authenticationContext = authenticationContext
        self.authenticationContext.localizedReason = operationReason
    }

    func setAccessDeniedHandler(_ handler: (@Sendable (OSStatus) -> Void)?) {
        lock.lock()
        accessDeniedHandler = handler
        let notification: (handler: @Sendable (OSStatus) -> Void, status: OSStatus)?
        if let handler, let deniedStatus, !didNotifyAccessDenied {
            didNotifyAccessDenied = true
            notification = (handler, deniedStatus)
        } else {
            notification = nil
        }
        lock.unlock()
        if let notification {
            notification.handler(notification.status)
        }
    }

    func denyFurtherAccess(status: OSStatus = errSecUserCanceled) {
        lock.lock()
        let handler = recordDenialIfNeeded(status)
        lock.unlock()
        handler?(status)
    }

    func invalidateCachedValue(service: String, account: String) {
        lock.lock()
        cache.removeValue(forKey: CacheKey(service: service, account: account))
        lock.unlock()
    }

    func read(service: String, account: String, query: [String: Any]) throws -> Data? {
        let cacheKey = CacheKey(service: service, account: account)
        lock.lock()
        if let deniedStatus {
            lock.unlock()
            throw KeychainStoreError(status: deniedStatus)
        }
        if let cached = cache[cacheKey] {
            lock.unlock()
            switch cached {
            case .missing: return nil
            case .data(let data): return data
            }
        }

        let result = security.copyMatching(authenticated(query) as CFDictionary)
        switch result.status {
        case errSecSuccess:
            guard let data = result.data else {
                lock.unlock()
                throw KeychainStoreError(status: errSecDecode)
            }
            cache[cacheKey] = .data(data)
            lock.unlock()
            return data
        case errSecItemNotFound:
            cache[cacheKey] = .missing
            lock.unlock()
            return nil
        default:
            let handler = recordDenialIfNeeded(result.status)
            lock.unlock()
            handler?(result.status)
            throw KeychainStoreError(status: result.status)
        }
    }

    func write(
        _ data: Data,
        service: String,
        account: String,
        query: [String: Any],
        attributes: [String: Any]
    ) throws {
        let cacheKey = CacheKey(service: service, account: account)
        lock.lock()
        if let deniedStatus {
            lock.unlock()
            throw KeychainStoreError(status: deniedStatus)
        }
        if case .data(let cached)? = cache[cacheKey], cached == data {
            lock.unlock()
            return
        }

        let authenticatedQuery = authenticated(query)
        let updateStatus = security.update(
            authenticatedQuery as CFDictionary,
            attributes: attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            cache[cacheKey] = .data(data)
            lock.unlock()
            return
        }
        if updateStatus != errSecItemNotFound {
            let handler = recordDenialIfNeeded(updateStatus)
            lock.unlock()
            handler?(updateStatus)
            throw KeychainStoreError(status: updateStatus)
        }

        var insertion = authenticatedQuery
        insertion.merge(attributes) { _, new in new }
        let addStatus = security.add(insertion as CFDictionary)
        guard addStatus == errSecSuccess else {
            let handler = recordDenialIfNeeded(addStatus)
            lock.unlock()
            handler?(addStatus)
            throw KeychainStoreError(status: addStatus)
        }
        cache[cacheKey] = .data(data)
        lock.unlock()
    }

    func delete(service: String, account: String, query: [String: Any]) throws {
        let cacheKey = CacheKey(service: service, account: account)
        lock.lock()
        if let deniedStatus {
            lock.unlock()
            throw KeychainStoreError(status: deniedStatus)
        }
        if case .missing? = cache[cacheKey] {
            lock.unlock()
            return
        }

        let status = security.delete(authenticated(query) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let handler = recordDenialIfNeeded(status)
            lock.unlock()
            handler?(status)
            throw KeychainStoreError(status: status)
        }
        cache[cacheKey] = .missing
        lock.unlock()
    }

    func deleteAll(service: String, query: [String: Any]) throws {
        lock.lock()
        if let deniedStatus {
            lock.unlock()
            throw KeychainStoreError(status: deniedStatus)
        }
        let status = security.delete(authenticated(query) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let handler = recordDenialIfNeeded(status)
            lock.unlock()
            handler?(status)
            throw KeychainStoreError(status: status)
        }
        cache = cache.filter { $0.key.service != service }
        lock.unlock()
    }

    private func authenticated(_ query: [String: Any]) -> [String: Any] {
        var query = query
        query[kSecUseAuthenticationContext as String] = authenticationContext
        return query
    }

    private func recordDenialIfNeeded(
        _ status: OSStatus
    ) -> (@Sendable (OSStatus) -> Void)? {
        guard status == errSecUserCanceled || status == errSecAuthFailed else { return nil }
        if deniedStatus == nil { deniedStatus = status }
        guard !didNotifyAccessDenied, let accessDeniedHandler else { return nil }
        didNotifyAccessDenied = true
        return accessDeniedHandler
    }
}

struct KeychainStore: Sendable {
    static let defaultOperationReason =
        "로그인 상태와 그룹 초대 코드를 안전하게 불러옵니다."

    let service: String
    let operationReason: String
    private let session: KeychainAccessSession

    init(
        service: String = "com.sidey.desktop",
        operationReason: String = Self.defaultOperationReason,
        session: KeychainAccessSession? = nil
    ) {
        self.service = service
        self.operationReason = operationReason
        if let session {
            self.session = session
        } else if operationReason == Self.defaultOperationReason {
            self.session = .shared
        } else {
            self.session = KeychainAccessSession(operationReason: operationReason)
        }
    }

    func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return try session.read(service: service, account: account, query: query)
    }

    func write(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        try session.write(
            data,
            service: service,
            account: account,
            query: baseQuery(account: account),
            attributes: attributes
        )
    }

    func delete(account: String) throws {
        try session.delete(
            service: service,
            account: account,
            query: baseQuery(account: account)
        )
    }

    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        try session.deleteAll(service: service, query: query)
    }

    func readString(account: String) throws -> String? {
        guard let data = try read(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func readFreshString(account: String) throws -> String? {
        session.invalidateCachedValue(service: service, account: account)
        return try readString(account: account)
    }

    func writeString(_ value: String, account: String) throws {
        try write(Data(value.utf8), account: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainStoreError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 오류 \(status)"
    }
}

/// Supabase의 전체 세션과 기존 Godot 클라이언트의 refresh token을 함께 갱신한다.
/// 네이티브 알파를 롤백해도 익명 계정이 끊기지 않게 하는 호환 계층이다.
struct SideyAuthStorage: AuthLocalStorage, Sendable {
    let keychain: KeychainStore
    let legacyRefreshAccount: String

    func store(key: String, value: Data) throws {
        try keychain.write(value, account: key)
        if let object = try? JSONSerialization.jsonObject(with: value) as? [String: Any],
           let refreshToken = object["refresh_token"] as? String,
           !refreshToken.isEmpty {
            try keychain.writeString(refreshToken, account: legacyRefreshAccount)
        }
    }

    func retrieve(key: String) throws -> Data? {
        try keychain.read(account: key)
    }

    func remove(key: String) throws {
        try keychain.delete(account: key)
    }
}
