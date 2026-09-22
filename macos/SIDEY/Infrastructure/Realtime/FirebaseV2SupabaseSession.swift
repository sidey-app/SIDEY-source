import Foundation

struct FirebaseV2SupabaseSession: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    let accessToken: String
    let identity: RealtimeCredentialIdentity

    var description: String { "<redacted Supabase Firebase bootstrap session>" }
    var debugDescription: String { description }
}

enum FirebaseV2SupabaseSessionError: Error, Equatable {
    case malformedToken
    case accountMismatch
    case missingSessionID
}

enum FirebaseV2SupabaseSessionDecoder {
    static func decode(
        accessToken: String,
        expectedAccountID: UUID
    ) throws -> FirebaseV2SupabaseSession {
        let components = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let payloadData = decodeBase64URL(String(components[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let rawAccountID = payload["sub"] as? String,
              let accountID = UUID(uuidString: rawAccountID) else {
            throw FirebaseV2SupabaseSessionError.malformedToken
        }
        guard accountID == expectedAccountID else {
            throw FirebaseV2SupabaseSessionError.accountMismatch
        }
        guard let rawSessionID = payload["session_id"] as? String,
              let sessionID = UUID(uuidString: rawSessionID) else {
            throw FirebaseV2SupabaseSessionError.missingSessionID
        }
        return FirebaseV2SupabaseSession(
            accessToken: accessToken,
            identity: RealtimeCredentialIdentity(
                accountID: accountID,
                sessionID: sessionID
            )
        )
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }
}
