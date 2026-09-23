import FirebaseDatabase
import Foundation

enum FirebaseV2DatabaseWriteOperation: Equatable, Sendable {
    case setServerTimestamp(path: String)
    case setThrow(path: String, targetUserID: UUID, wireCode: FirebaseV2WireCode)
    case remove(path: String)
}

protocol FirebaseV2DatabaseWriteTransport: Sendable {
    func perform(_ operation: FirebaseV2DatabaseWriteOperation) async throws
}

final class FirebaseV2DatabaseWriteAdapter: @unchecked Sendable, FirebaseV2DatabaseWriteTransport {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func perform(_ operation: FirebaseV2DatabaseWriteOperation) async throws {
        switch operation {
        case .setServerTimestamp(let path):
            try await setValue(ServerValue.timestamp(), at: path)
        case .setThrow(let path, let targetUserID, let wireCode):
            try await setValue([
                "u": targetUserID.uuidString.lowercased(),
                "k": wireCode.rawValue,
                "t": ServerValue.timestamp(),
            ], at: path)
        case .remove(let path):
            try await removeValue(at: path)
        }
    }

    private func setValue(_ value: Any, at path: String) async throws {
        let reference = database.reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setValue(value) { error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func removeValue(at path: String) async throws {
        let reference = database.reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.removeValue { error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct FirebaseV2TransientContext: Equatable, Sendable {
    let identity: RealtimeCredentialIdentity
    let activeRoomID: UUID
    let throwableWireCodesByCatalogID: [String: FirebaseV2WireCode]
    var authorizedWireCodes: Set<FirebaseV2WireCode>
}

enum FirebaseV2TransientWriterError: Error, Equatable {
    case inactiveRoom
    case unsupportedTypingEvent
    case wireCodeUnavailable
}

actor FirebaseV2TransientWriter {
    private let transport: any FirebaseV2DatabaseWriteTransport
    private var context: FirebaseV2TransientContext

    init(
        transport: any FirebaseV2DatabaseWriteTransport,
        context: FirebaseV2TransientContext
    ) {
        self.transport = transport
        self.context = context
    }

    func replaceContext(_ context: FirebaseV2TransientContext) {
        self.context = context
    }

    func publishTyping(roomID: UUID, event: String) async throws {
        try requireActive(roomID)
        let path = FirebaseV2Path.typing(
            roomID: roomID,
            userID: context.identity.accountID,
            sessionID: context.identity.sessionID
        )
        switch event {
        case "typing_start", "typing_keepalive":
            try await transport.perform(.setServerTimestamp(path: path))
        case "typing_stop":
            try await transport.perform(.remove(path: path))
        default:
            throw FirebaseV2TransientWriterError.unsupportedTypingEvent
        }
    }

    func publishPulse(roomID: UUID) async throws {
        try requireActive(roomID)
        try await transport.perform(.setServerTimestamp(path: FirebaseV2Path.pulse(
            roomID: roomID,
            userID: context.identity.accountID
        )))
    }

    func publishThrow(
        roomID: UUID,
        targetUserID: UUID,
        catalogItemID: String
    ) async throws {
        try requireActive(roomID)
        guard let wireCode = context.throwableWireCodesByCatalogID[catalogItemID],
              context.authorizedWireCodes.contains(wireCode) else {
            throw FirebaseV2TransientWriterError.wireCodeUnavailable
        }
        try await transport.perform(.setThrow(
            path: FirebaseV2Path.characterThrow(
                roomID: roomID,
                userID: context.identity.accountID
            ),
            targetUserID: targetUserID,
            wireCode: wireCode
        ))
    }

    private func requireActive(_ roomID: UUID) throws {
        guard context.activeRoomID == roomID else {
            throw FirebaseV2TransientWriterError.inactiveRoom
        }
    }
}
