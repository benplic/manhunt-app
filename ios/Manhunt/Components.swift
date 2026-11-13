import SwiftUI

struct TopoField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<8 {
                var path = Path()
                let inset = CGFloat(index) * 22
                let rect = CGRect(
                    x: -80 + inset * 0.4,
                    y: size.height * 0.18 + CGFloat(index) * 34,
                    width: size.width + 160 - inset,
                    height: 180 + CGFloat(index) * 8
                )
                path.addEllipse(in: rect)
                context.stroke(
                    path,
                    with: .color(HuntColor.signal.opacity(0.14 + Double(index) * 0.015)),
                    lineWidth: 1
                )
            }
        }
        .background(HuntColor.ink)
        .ignoresSafeArea()
    }
}

struct ScreenHeader: View {
    var title: String
    var subtitle: String?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(HuntColor.inkRaised, in: Circle())
                }
                .buttonStyle(.huntPress)
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HuntFont.title(32))
                    .foregroundStyle(HuntColor.paper)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(HuntColor.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct HuntButton: View {
    var title: String
    var systemImage: String?
    var tint: Color = HuntColor.signal
    var ink: Color = HuntColor.ink
    var haptic: HuntHaptic = .medium
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(ink)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.huntPress(haptic))
    }
}

struct RolePill: View {
    var role: VisualRole

    var body: some View {
        Text(role.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(HuntColor.ink)
            .background(role.tint, in: Capsule())
    }
}

struct CodeReadout: View {
    var code: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(code.prefix(6).enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .frame(width: 36, height: 48)
                    .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(HuntColor.line, lineWidth: 1)
                    )
            }
        }
        .foregroundStyle(HuntColor.paper)
        .accessibilityLabel("Join code \(code)")
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HuntColor.inkRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HuntColor.line, lineWidth: 1)
            )
    }
}
