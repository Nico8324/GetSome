/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A full-screen biometric lock view that appears when the app comes to the foreground
and the user has enabled biometric authentication.
*/

// tvOS ships no LocalAuthentication framework — there's no biometric sensor on a
// television — so the lock doesn't exist there at all. ContentView and ProfileView
// check the same condition rather than referring to this type unconditionally.
#if canImport(LocalAuthentication)
import SwiftUI
import LocalAuthentication

/// A full-screen lock view that requires biometric authentication to proceed.
///
/// The view automatically triggers authentication when it appears. Users can retry
/// by tapping the Unlock button. On successful authentication, the view calls its
/// completion closure and dismisses itself.
struct AppLockView: View {
    /// Called when the user successfully authenticates.
    let onUnlocked: () -> Void

    @State private var isAuthenticating = false
    @State private var authenticationError: String?

    var body: some View {
        VStack(spacing: Constants.verticalTextSpacing) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("GetSome")
                .font(.largeTitle.bold())

            Text("This app requires authentication")
                .font(.headline)

            if let error = authenticationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("Unlock") {
                Task {
                    await authenticate()
                }
            }
            .buttonStyle(CustomButtonStyle())
            .disabled(isAuthenticating)

            .padding(.bottom, Constants.outerPadding)
        }
        .padding(Constants.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .background(.black)
        .ignoresSafeArea()
        .onAppear {
            Task {
                await authenticate()
            }
        }
    }

    /// Attempts to authenticate the user using biometric authentication (Face ID or Touch ID).
    ///
    /// Each authentication attempt uses a fresh LAContext to ensure a clean state.
    /// If authentication fails, the error is displayed and the user can retry via the button.
    /// On success, the onUnlocked closure is called.
    private func authenticate() async {
        isAuthenticating = true
        authenticationError = nil

        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available with passcode fallback.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = "Authentication unavailable"
            isAuthenticating = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to access GetSome"
            )

            if success {
                onUnlocked()
            }
        } catch let error as LAError {
            // Ignore user cancellation and other transient errors.
            if error.code != .userCancel && error.code != .systemCancel {
                authenticationError = "Authentication failed"
            }
        } catch {
            authenticationError = "Authentication failed"
        }

        isAuthenticating = false
    }
}

#Preview {
    AppLockView {
        print("Unlocked")
    }
}

#endif
