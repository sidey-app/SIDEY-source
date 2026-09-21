import LocalAuthentication
import Security
import XCTest
@testable import SIDEY

final class KeychainStoreTests: XCTestCase {
    func testDefaultOperationReasonExplainsWhySIDEYUsesKeychain() {
        XCTAssertEqual(
            KeychainStore.defaultOperationReason,
            L10n.text("keychain.operation_reason")
        )
    }

    func testTransitionNoticeUsesApprovedCopy() {
        XCTAssertEqual(
            KeychainTransitionNotice.message,
            L10n.text("keychain.transition.message")
        )
        XCTAssertEqual(
            KeychainTransitionNotice.migrationExplanation,
            L10n.text("keychain.transition.migration_explanation")
        )
        XCTAssertEqual(
            KeychainTransitionNotice.privacyExplanation,
            L10n.text("keychain.transition.privacy_explanation")
        )
    }

    func testSessionReusesAuthenticationContextAcrossSecurityCalls() throws {
        let security = FakeKeychainSecurity()
        let session = KeychainAccessSession(security: security)
        let store = KeychainStore(service: "context-test", session: session)

        XCTAssertNil(try store.read(account: "first"))
        XCTAssertNil(try store.read(account: "second"))

        XCTAssertEqual(security.authenticationContextIDs.count, 2)
        XCTAssertEqual(Set(security.authenticationContextIDs).count, 1)
    }

    func testRepeatedReadUsesMemoryCache() throws {
        let data = Data("cached-session".utf8)
        let security = FakeKeychainSecurity(values: ["session": data])
        let session = KeychainAccessSession(security: security)
        let store = KeychainStore(service: "read-cache-test", session: session)

        XCTAssertEqual(try store.read(account: "session"), data)
        XCTAssertEqual(try store.read(account: "session"), data)

        XCTAssertEqual(security.copyCallCount, 1)
    }

    func testFreshReadReloadsValueChangedOutsideTheAccessSession() throws {
        let security = FakeKeychainSecurity()
        let session = KeychainAccessSession(security: security)
        let store = KeychainStore(service: "fresh-read-test", session: session)

        XCTAssertNil(try store.readString(account: "refresh-token"))
        security.replaceExternally(
            account: "refresh-token",
            value: Data("new-token".utf8)
        )
        XCTAssertNil(try store.readString(account: "refresh-token"))

        XCTAssertEqual(
            try store.readFreshString(account: "refresh-token"),
            "new-token"
        )
        XCTAssertEqual(security.copyCallCount, 2)
    }

    func testSessionRestorerUsesFreshTokenWhenCurrentSessionIsMissing() async throws {
        let restorer = AuthSessionRestorer(
            loadCurrentSession: { () async throws -> String in
                throw SessionRestorerTestError.missing
            },
            isSessionMissing: { ($0 as? SessionRestorerTestError) == .missing },
            loadFreshRefreshToken: { "rotated-refresh-token" },
            refreshSession: { "restored:\($0)" }
        )

        let session = try await restorer.session()

        XCTAssertEqual(session, "restored:rotated-refresh-token")
    }

    func testSessionRestorerDoesNotHideNonSessionFailure() async {
        let restorer = AuthSessionRestorer(
            loadCurrentSession: { () async throws -> String in
                throw SessionRestorerTestError.network
            },
            isSessionMissing: { ($0 as? SessionRestorerTestError) == .missing },
            loadFreshRefreshToken: { "unused" },
            refreshSession: { _ in "unused" }
        )

        do {
            _ = try await restorer.session()
            XCTFail("원래 오류를 전달해야 함")
        } catch {
            XCTAssertEqual(error as? SessionRestorerTestError, .network)
        }
    }

    func testWritingIdenticalCachedDataSkipsSecurityCall() throws {
        let data = Data("same-session".utf8)
        let security = FakeKeychainSecurity(values: ["session": data])
        let session = KeychainAccessSession(security: security)
        let store = KeychainStore(service: "write-cache-test", session: session)
        XCTAssertEqual(try store.read(account: "session"), data)

        try store.write(data, account: "session")

        XCTAssertEqual(security.updateCallCount, 0)
        XCTAssertEqual(security.addCallCount, 0)
    }

    func testDenialNotifiesOnceAndBlocksLaterSecurityCalls() {
        let security = FakeKeychainSecurity(copyStatus: errSecUserCanceled)
        let counter = LockedCounter()
        let session = KeychainAccessSession(security: security)
        session.setAccessDeniedHandler { _ in counter.increment() }
        let store = KeychainStore(service: "denial-test", session: session)

        XCTAssertThrowsError(try store.read(account: "first"))
        XCTAssertThrowsError(try store.read(account: "second"))
        XCTAssertThrowsError(try store.write(Data("blocked".utf8), account: "third"))

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(security.copyCallCount, 1)
        XCTAssertEqual(security.updateCallCount, 0)
        XCTAssertEqual(security.addCallCount, 0)
    }

    func testExplicitDenialBlocksSecurityBeforeFirstCall() {
        let security = FakeKeychainSecurity()
        let counter = LockedCounter()
        let session = KeychainAccessSession(security: security)
        session.setAccessDeniedHandler { _ in counter.increment() }

        session.denyFurtherAccess()
        let store = KeychainStore(service: "explicit-denial-test", session: session)

        XCTAssertThrowsError(try store.read(account: "session"))
        XCTAssertThrowsError(try store.write(Data("blocked".utf8), account: "session"))
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(security.copyCallCount, 0)
        XCTAssertEqual(security.updateCallCount, 0)
        XCTAssertEqual(security.addCallCount, 0)
    }

    func testKeychainRoundTripAndDeletion() throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let account = "round-trip"
        defer { try? store.delete(account: account) }

        try store.writeString("SIDEY-비밀값", account: account)
        XCTAssertEqual(try store.readString(account: account), "SIDEY-비밀값")
        try store.delete(account: account)
        XCTAssertNil(try store.read(account: account))
    }

    func testSupabaseStorageMirrorsRefreshTokenForRollback() throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let sessionAccount = "native-session"
        let legacyAccount = "legacy-refresh"
        defer {
            try? store.delete(account: sessionAccount)
            try? store.delete(account: legacyAccount)
        }
        let storage = SideyAuthStorage(keychain: store, legacyRefreshAccount: legacyAccount)
        let session = Data(#"{"access_token":"access","refresh_token":"keep-this-account"}"#.utf8)

        try storage.store(key: sessionAccount, value: session)

        XCTAssertEqual(try storage.retrieve(key: sessionAccount), session)
        XCTAssertEqual(try store.readString(account: legacyAccount), "keep-this-account")
    }

    func testNativeBackendReadsGodotInviteCodeAccount() async throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let configuration = try RuntimeConfiguration.resolve(releaseChannel: .appStore, environment: [:])
        let roomID = try XCTUnwrap(UUID(uuidString: "A33009C1-B56D-4DEB-9CF2-ECEB778B658F"))
        let godotAccount = "room-invite:\(configuration.backendFingerprint):default:\(roomID.uuidString.lowercased())"
        defer { try? store.delete(account: godotAccount) }
        try store.writeString("SIDEY-LEGACY-CODE", account: godotAccount)
        let backend = SideyBackend(configuration: configuration, keychain: store)

        let migrated = try await backend.storedInviteCode(roomID: roomID)

        XCTAssertEqual(migrated, "SIDEY-LEGACY-CODE")
        await backend.shutdown()
    }

    func testExistingLocalIdentityNeverCreatesReplacementAnonymousSession() async throws {
        let store = KeychainStore(service: "app.sidey.desktop.tests.\(UUID().uuidString)")
        let configuration = try RuntimeConfiguration.resolve(releaseChannel: .appStore, environment: [:])
        let backend = SideyBackend(configuration: configuration, keychain: store)

        do {
            _ = try await backend.boot(requireExistingSession: true)
            XCTFail("기존 로컬 계정은 세션 복구 실패 시 새 익명 계정을 만들면 안 됨")
        } catch let error as SideyBackendError {
            XCTAssertEqual(error, .sessionRecoveryFailed)
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }
        await backend.shutdown()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class FakeKeychainSecurity: KeychainSecurityPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data]
    private let copyStatus: OSStatus?
    private var copyCalls = 0
    private var updateCalls = 0
    private var addCalls = 0
    private var contextIDs: [ObjectIdentifier] = []

    init(values: [String: Data] = [:], copyStatus: OSStatus? = nil) {
        self.values = values
        self.copyStatus = copyStatus
    }

    var copyCallCount: Int { locked { copyCalls } }
    var updateCallCount: Int { locked { updateCalls } }
    var addCallCount: Int { locked { addCalls } }
    var authenticationContextIDs: [ObjectIdentifier] { locked { contextIDs } }

    func replaceExternally(account: String, value: Data) {
        lock.lock()
        values[account] = value
        lock.unlock()
    }

    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        lock.lock()
        defer { lock.unlock() }
        copyCalls += 1
        recordAuthenticationContext(from: query)
        if let copyStatus { return (copyStatus, nil) }
        guard let account = dictionary(query)[kSecAttrAccount as String] as? String,
              let data = values[account]
        else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        updateCalls += 1
        recordAuthenticationContext(from: query)
        guard let account = dictionary(query)[kSecAttrAccount as String] as? String,
              values[account] != nil
        else { return errSecItemNotFound }
        if let data = dictionary(attributes)[kSecValueData as String] as? Data {
            values[account] = data
        }
        return errSecSuccess
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        addCalls += 1
        recordAuthenticationContext(from: attributes)
        guard let account = dictionary(attributes)[kSecAttrAccount as String] as? String,
              let data = dictionary(attributes)[kSecValueData as String] as? Data
        else { return errSecParam }
        values[account] = data
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        recordAuthenticationContext(from: query)
        guard let account = dictionary(query)[kSecAttrAccount as String] as? String else {
            values.removeAll()
            return errSecSuccess
        }
        return values.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
    }

    private func recordAuthenticationContext(from dictionary: CFDictionary) {
        if let context = self.dictionary(dictionary)[kSecUseAuthenticationContext as String] as? LAContext {
            contextIDs.append(ObjectIdentifier(context))
        }
    }

    private func dictionary(_ value: CFDictionary) -> NSDictionary {
        value as NSDictionary
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private enum SessionRestorerTestError: Error, Equatable {
    case missing
    case network
}
