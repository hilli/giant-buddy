import Foundation
import AuthenticationServices
import Security

/// Handles Strava OAuth authentication and ride uploads.
@MainActor
class StravaService: NSObject, ObservableObject {

    static let shared = StravaService()

    @Published var isConnected = false
    @Published var athleteName: String?
    @Published var isUploading = false
    @Published var lastUploadError: String?

    var autoUpload: Bool {
        get { UserDefaults.standard.bool(forKey: "stravaAutoUpload") }
        set { UserDefaults.standard.set(newValue, forKey: "stravaAutoUpload") }
    }

    private let callbackScheme = "giantlogger"
    private let redirectURI = "giantlogger://strava"
    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        // Restore connection state from Keychain
        if loadTokens() != nil {
            isConnected = true
            athleteName = UserDefaults.standard.string(forKey: "stravaAthleteName")
        }
    }

    // MARK: - OAuth

    func authenticate() {
        let scopes = "activity:write,read"
        let urlString = "https://www.strava.com/oauth/mobile/authorize"
            + "?client_id=\(StravaSecrets.clientID)"
            + "&redirect_uri=\(redirectURI)"
            + "&response_type=code"
            + "&approval_prompt=auto"
            + "&scope=\(scopes)"

        guard let url = URL(string: urlString) else { return }

        // Try native Strava app first, fall back to web
        if UIApplication.shared.canOpenURL(URL(string: "strava://")!) {
            let stravaURL = URL(string: urlString.replacingOccurrences(
                of: "https://www.strava.com/oauth/mobile/authorize",
                with: "strava://oauth/mobile/authorize"
            ))!
            UIApplication.shared.open(stravaURL)
        } else {
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                guard let self else { return }
                if let callbackURL {
                    Task { @MainActor in
                        await self.handleCallback(callbackURL)
                    }
                } else if let error {
                    self.lastUploadError = error.localizedDescription
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
            authSession = session
        }
    }

    /// Handle the OAuth callback URL (from ASWebAuthenticationSession or deep link).
    func handleCallback(_ url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            lastUploadError = "No authorization code received"
            return
        }
        await exchangeCode(code)
    }

    func disconnect() {
        deleteTokens()
        isConnected = false
        athleteName = nil
        UserDefaults.standard.removeObject(forKey: "stravaAthleteName")
        UserDefaults.standard.set(false, forKey: "stravaAutoUpload")
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String) async {
        let params: [String: String] = [
            "client_id": StravaSecrets.clientID,
            "client_secret": StravaSecrets.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]

        do {
            let result = try await postTokenRequest(params)
            if let accessToken = result["access_token"] as? String,
               let refreshToken = result["refresh_token"] as? String,
               let expiresAt = result["expires_at"] as? Int {
                saveTokens(access: accessToken, refresh: refreshToken, expiresAt: expiresAt)
                isConnected = true

                if let athlete = result["athlete"] as? [String: Any],
                   let first = athlete["firstname"] as? String,
                   let last = athlete["lastname"] as? String {
                    let name = "\(first) \(last)"
                    athleteName = name
                    UserDefaults.standard.set(name, forKey: "stravaAthleteName")
                }
            }
        } catch {
            lastUploadError = "Token exchange failed: \(error.localizedDescription)"
        }
    }

    private func refreshTokenIfNeeded() async throws -> String {
        guard let tokens = loadTokens() else {
            throw StravaError.notConnected
        }

        // Token still valid (with 60s buffer)
        if Date().timeIntervalSince1970 < Double(tokens.expiresAt - 60) {
            return tokens.access
        }

        let params: [String: String] = [
            "client_id": StravaSecrets.clientID,
            "client_secret": StravaSecrets.clientSecret,
            "refresh_token": tokens.refresh,
            "grant_type": "refresh_token"
        ]

        let result = try await postTokenRequest(params)
        guard let accessToken = result["access_token"] as? String,
              let refreshToken = result["refresh_token"] as? String,
              let expiresAt = result["expires_at"] as? Int else {
            throw StravaError.tokenRefreshFailed
        }

        saveTokens(access: accessToken, refresh: refreshToken, expiresAt: expiresAt)
        return accessToken
    }

    private func postTokenRequest(_ params: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw StravaError.apiError("Token request failed: \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StravaError.apiError("Invalid JSON response")
        }
        return json
    }

    // MARK: - Upload

    func uploadRide(_ ride: Ride) async throws {
        isUploading = true
        lastUploadError = nil
        defer { isUploading = false }

        let accessToken = try await refreshTokenIfNeeded()
        let gpxContent = ExportService.exportGPX(ride: ride)

        guard let gpxData = gpxContent.data(using: .utf8) else {
            throw StravaError.apiError("Failed to encode GPX")
        }

        let boundary = UUID().uuidString
        let dateStr = ride.startDate.formatted(.dateTime.month().day().year())
        let name = "Giant E-Bike Ride \(dateStr)"

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("data_type", "gpx")
        appendField("activity_type", "ebikeride")
        appendField("name", name)
        appendField("description", "Recorded with Giant Buddy")
        appendField("external_id", ride.id.uuidString)

        // File part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"ride.gpx\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(gpxData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.apiError("No HTTP response")
        }

        if !(200...299).contains(http.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw StravaError.apiError("Upload failed (\(http.statusCode)): \(responseBody)")
        }
    }

    // MARK: - Keychain

    private struct TokenData {
        let access: String
        let refresh: String
        let expiresAt: Int
    }

    private let keychainService = "dk.hilli.GiantLogger.strava"

    private func saveTokens(access: String, refresh: String, expiresAt: Int) {
        let data = "\(access)|\(refresh)|\(expiresAt)".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "tokens"
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadTokens() -> TokenData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "tokens",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }

        let parts = str.split(separator: "|")
        guard parts.count == 3, let expiresAt = Int(parts[2]) else { return nil }
        return TokenData(access: String(parts[0]), refresh: String(parts[1]), expiresAt: expiresAt)
    }

    private func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "tokens"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension StravaService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first {
            return window
        }
        guard let scene = scenes.first else {
            preconditionFailure("Strava authentication requires an active window scene")
        }
        return ASPresentationAnchor(windowScene: scene)
    }
}

// MARK: - Errors

enum StravaError: LocalizedError {
    case notConnected
    case tokenRefreshFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Strava"
        case .tokenRefreshFailed: return "Failed to refresh Strava token"
        case .apiError(let msg): return msg
        }
    }
}
