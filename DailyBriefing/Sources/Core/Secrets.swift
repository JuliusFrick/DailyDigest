import Foundation

/// Holds secret configuration values that should not be exposed in public repositories unless encrypted.
/// For the "Pleasant" user experience, the developer should populate these values.
struct Secrets {
    /// The Google OAuth Client ID for the application.
    /// If provided, users will not be asked to configure their own Project.
    static let googleClientId: String = ""
    
    /// The Google OAuth Client Secret (if required for the client type).
    /// For "Desktop" clients using loopback, this might be required depending on setup.
    static let googleClientSecret: String = ""
}
