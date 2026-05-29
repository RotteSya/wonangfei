import SwiftUI

struct WNFHeaderIconButton: View {
    var systemName: String
    var accessibilityLabel: String
    var isLoading = false
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(WNFTheme.ink)
                        .scaleEffect(0.68)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .animation(.easeInOut(duration: 0.14), value: isLoading)
        .accessibilityLabel(accessibilityLabel)
    }
}
