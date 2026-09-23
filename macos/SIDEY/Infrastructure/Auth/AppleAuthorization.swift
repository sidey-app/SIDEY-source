import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct AppleAuthorizationPayload: Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String
}

enum AppleAuthorization {
    static func prepare(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.state = nonce
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func payload(
        from result: Result<ASAuthorization, any Error>
    ) throws -> AppleAuthorizationPayload {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else { throw AppleAuthorizationError.missingIdentityToken }
        guard let nonce = credential.state, !nonce.isEmpty else {
            throw AppleAuthorizationError.missingRequestNonce
        }
        let authorizationCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        return AppleAuthorizationPayload(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: nonce
        )
    }

    static func makeNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            if byte < alphabet.count { result.append(alphabet[Int(byte)]) }
        }
        return result
    }
}

enum AppleAuthorizationError: LocalizedError {
    case missingIdentityToken
    case missingRequestNonce
    case missingAuthorizationCode

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: L10n.text("apple_auth.error.missing_identity_token")
        case .missingRequestNonce: L10n.text("apple_auth.error.missing_request_nonce")
        case .missingAuthorizationCode:
            L10n.text("apple_auth.error.missing_authorization_code")
        }
    }
}
