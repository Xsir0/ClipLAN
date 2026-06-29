import SwiftUI

struct PasteLogoMark: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.accentColor)

            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: max(1.4, size * 0.07))
                .frame(width: size * 0.46, height: size * 0.58)
                .offset(x: size * 0.06, y: size * 0.05)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.30, height: size * 0.10)
                .offset(x: size * 0.06, y: -size * 0.28)

            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: max(1.2, size * 0.06))
                .frame(width: size * 0.38, height: size * 0.48)
                .offset(x: -size * 0.10, y: -size * 0.04)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
