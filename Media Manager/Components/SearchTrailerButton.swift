import SwiftUI

struct SearchTrailerButton: View {
    let isLoading: Bool
    let isUnavailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: isUnavailable ? "xmark.circle.fill" : "play.circle.fill")
                        .font(.system(size: 14))
                }

                Text(isUnavailable ? "No Trailer" : "Watch Trailer")
                    .font(AppTypography.caption1(.semibold))
            }
            .foregroundColor(isUnavailable ? ColorPalette.textMutedDark : .white)
            .frame(width: 126, height: 34)
            .background(isUnavailable ? ColorPalette.divider.opacity(0.35) : Color.red.opacity(0.9))
            .cornerRadius(AppRadius.sm)
        }
        .disabled(isLoading || isUnavailable)
    }
}
