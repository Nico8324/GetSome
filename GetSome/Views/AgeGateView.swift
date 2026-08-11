/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that asks a person to confirm their age before showing any content.
*/

import SwiftUI

/// A view that asks a person to confirm their age before showing any content.
///
/// The source site serves adult content, so the app doesn't load a single video
/// until a person confirms they're old enough to see it.
struct AgeGateView: View {
    /// An action the view performs when a person confirms their age.
    let confirm: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Constants.verticalTextSpacing) {
            Spacer()

            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("GetSome")
                .font(.largeTitle.bold())

            Text("This app shows adult content from mat6tube.com.")
                .font(.headline)

            Text("""
                You must be at least 18 years old, or the age of majority where you live, \
                to continue. All videos stream from the source site.
                """)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Constants.ageGateTextWidth)

            Spacer()

            VStack(spacing: Constants.genreSpacing) {
                Button("I’m 18 or older — continue", action: confirm)
                    .buttonStyle(CustomButtonStyle())

                Button("Leave") {
                    openURL(URL(string: "https://www.apple.com")!)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.footnote)
            }
            .padding(.bottom, Constants.outerPadding)
        }
        .padding(Constants.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        #if !os(tvOS)
        .background(.black)
        #endif
    }
}

#Preview {
    AgeGateView {}
}
