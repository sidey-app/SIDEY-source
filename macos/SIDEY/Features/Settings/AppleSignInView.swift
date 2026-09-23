import AuthenticationServices
import SwiftUI

struct AppleSignInView: View {
    @Bindable var model: AppModel
    let onSignIn: (AppleAuthorizationPayload) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 54))
                .foregroundStyle(.mint)
            VStack(spacing: 8) {
                Text("auth.apple.title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("auth.apple.description")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            SignInWithAppleButton(.continue) { request in
                let nonce = AppleAuthorization.makeNonce()
                AppleAuthorization.prepare(request, nonce: nonce)
            } onCompletion: { result in
                do {
                    onSignIn(try AppleAuthorization.payload(from: result))
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 280, height: 44)
            .disabled(model.accountOperationInProgress)

            if model.accountOperationInProgress { ProgressView("auth.apple.verifying") }
            if let error = model.errorMessage {
                Text(verbatim: error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
