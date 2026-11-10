import AuthenticationServices
import Foundation

/// Presents Sign in with Apple and extracts the identity token.
enum AppleSignIn {
    static func identityToken(from credential: ASAuthorizationAppleIDCredential) -> String? {
        guard let data = credential.identityToken else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
