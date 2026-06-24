import SwiftUI

// MARK: - 主题与可复用样式

enum Theme {
    /// 品牌主色：沉稳的科技蓝
    static let accent = Color(red: 0.20, green: 0.48, blue: 0.95)
    static let accentPressed = Color(red: 0.15, green: 0.40, blue: 0.85)

    /// 成功色
    static let success = Color(red: 0.22, green: 0.70, blue: 0.40)

    /// 警示色
    static let danger = Color(red: 0.90, green: 0.35, blue: 0.35)

    /// 渐变背景
    private static let gradientTop = Color(red: 0.97, green: 0.98, blue: 0.99)
    private static let gradientBottom = Color(red: 0.91, green: 0.93, blue: 0.97)

    static let secondaryText = Color.secondary

    /// 整体渐变背景
    static func gradientBackground() -> LinearGradient {
        LinearGradient(
            colors: [gradientTop, gradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - 主按钮样式

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Theme.accentPressed : color)
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.15 : 0.3),
                    radius: configuration.isPressed ? 4 : 8, y: configuration.isPressed ? 2 : 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 圆形图标徽章

/// 带渐变背景与阴影的圆形图标容器，用于各状态页顶部视觉
struct IconBadge: View {
    let systemName: String
    let background: AnyShapeStyle
    let symbolColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.12), radius: 14, y: 8)
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundColor(symbolColor)
        }
    }
}
