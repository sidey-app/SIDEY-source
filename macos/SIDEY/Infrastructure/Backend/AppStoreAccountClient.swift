import Foundation

struct AppStoreAccountClient: Sendable {
    let verifierURL: URL?

    init(verifierURL: URL? = AppStoreServiceEndpoint.resolve()) {
        self.verifierURL = verifierURL
    }

    func deleteAccount(payload: AppleAuthorizationPayload, accessToken: String) async throws {
        guard let authorizationCode = payload.authorizationCode else {
            throw AppleAuthorizationError.missingAuthorizationCode
        }
        guard let verifierURL else { throw AppStorePurchaseError.verifierNotConfigured }
        var request = URLRequest(url: verifierURL.appending(path: "v1/accounts/delete"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteAccountRequest(
            identityToken: payload.identityToken,
            authorizationCode: authorizationCode,
            nonce: payload.nonce
        ))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppStoreAccountError.deletionRejected
        }
    }
}

private struct DeleteAccountRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
}

enum AppStoreAccountError: LocalizedError {
    case deletionRejected
    var errorDescription: String? { L10n.text("account_delete.error.request_failed") }
}
