import Foundation

enum FirebaseV2Endpoint {
    static let bootstrap = URL(
        string: "https://asia-southeast1-sidey-realtime.cloudfunctions.net/bootstrapRealtime"
    )!
}

struct FirebaseV2HTTPResponse: @unchecked Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol FirebaseV2HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> FirebaseV2HTTPResponse
}

struct FirebaseV2URLSessionTransport: FirebaseV2HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> FirebaseV2HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw FirebaseV2BootstrapClientError.invalidHTTPResponse
        }
        return FirebaseV2HTTPResponse(data: data, response: response)
    }
}

enum FirebaseV2BootstrapClientError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidHTTPResponse
    case server(FirebaseV2BootstrapFailure)
    case malformedSuccess
    case unexpectedContract

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            "Supabase 로그인 세션이 없어 Firebase 실시간 연결을 시작할 수 없습니다."
        case .invalidHTTPResponse:
            "Firebase bootstrap 응답을 확인할 수 없습니다."
        case .server(let failure):
            switch failure {
            case .invalidArgument:
                "Firebase bootstrap 요청 형식이 올바르지 않습니다."
            case .authenticationRequired:
                "Firebase 실시간 연결을 위해 다시 로그인해야 합니다."
            case .methodNotAllowed:
                "Firebase bootstrap 요청 방식이 서버 계약과 일치하지 않습니다."
            case .grantNotConverged:
                "Firebase 실시간 권한이 아직 준비되지 않았습니다."
            case .rolloutDisabled:
                "Firebase 실시간 rollout 승인이 만료되었거나 중지되었습니다."
            case .rateLimited:
                "Firebase 실시간 연결 요청이 너무 많습니다. 잠시 뒤 다시 시도해 주세요."
            case .unavailable, .unexpectedStatus:
                "Firebase 실시간 연결을 준비할 수 없습니다."
            }
        case .malformedSuccess:
            "Firebase bootstrap 성공 응답을 해석할 수 없습니다."
        case .unexpectedContract:
            "Firebase bootstrap 응답이 이 앱의 실시간 계약과 일치하지 않습니다."
        }
    }
}

struct FirebaseV2BootstrapClient: Sendable {
    private let transport: any FirebaseV2HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let nowMilliseconds: @Sendable () -> Int64

    init(
        transport: any FirebaseV2HTTPTransport = FirebaseV2URLSessionTransport(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.transport = transport
        self.encoder = encoder
        self.decoder = decoder
        self.nowMilliseconds = nowMilliseconds
    }

    func bootstrap(
        accessToken: String,
        minimumAccessRevision: RealtimeRevision? = nil
    ) async throws -> FirebaseV2BootstrapSuccess {
        guard !accessToken.isEmpty else {
            throw FirebaseV2BootstrapClientError.missingAccessToken
        }

        var request = URLRequest(url: FirebaseV2Endpoint.bootstrap)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(
            FirebaseV2BootstrapRequest(minimumAccessRevision: minimumAccessRevision)
        )

        let result = try await transport.data(for: request)
        guard result.response.statusCode == 200 else {
            let errorCode = (try? decoder.decode(
                FirebaseV2BootstrapErrorResponse.self,
                from: result.data
            ))?.error
            throw FirebaseV2BootstrapClientError.server(
                FirebaseV2BootstrapFailure(
                    statusCode: result.response.statusCode,
                    errorCode: errorCode
                )
            )
        }

        var success: FirebaseV2BootstrapSuccess
        do {
            success = try decoder.decode(FirebaseV2BootstrapSuccess.self, from: result.data)
        } catch {
            throw FirebaseV2BootstrapClientError.malformedSuccess
        }

        let receivedAtMilliseconds = nowMilliseconds()
        let serverNowMilliseconds = result.response.firebaseV2ServerDateMilliseconds
            ?? receivedAtMilliseconds
        do {
            try success.anchorRolloutLeaseSchedule(
                receivedAtMilliseconds: receivedAtMilliseconds,
                serverNowMilliseconds: serverNowMilliseconds
            )
        } catch {
            throw FirebaseV2BootstrapClientError.unexpectedContract
        }
        guard success.protocolVersion == 2,
              success.databaseURL == FirebaseV2Configuration.databaseURL,
              success.permissionSync == .eventDriven,
              success.authTokenLifetimeSeconds > 0,
              !success.firebaseApiKey.isEmpty else {
            throw FirebaseV2BootstrapClientError.unexpectedContract
        }
        return success
    }
}

private struct FirebaseV2BootstrapErrorResponse: Decodable {
    let error: String
}

private extension HTTPURLResponse {
    var firebaseV2ServerDateMilliseconds: Int64? {
        guard let rawDate = value(forHTTPHeaderField: "Date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: rawDate) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1_000)
    }
}
