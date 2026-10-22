import SwiftUI

// MARK: - 主题与可复用样式

enum Theme {
    /// 品牌主色：沉稳的科技蓝（与安装器保持一致）
    static let accent = Color(red: 0.20, green: 0.48, blue: 0.95)
    static let accentPressed = Color(red: 0.15, green: 0.40, blue: 0.85)

    /// 危险色：卸载动作使用
    static let danger = Color(red: 0.86, green: 0.28, blue: 0.28)
    static let dangerPressed = Color(red: 0.74, green: 0.20, blue: 0.20)

    /// 成功色
    static let success = Color(red: 0.22, green: 0.70, blue: 0.40)

    /// 警示色
    static let warning = Color(red: 0.85, green: 0.55, blue: 0.15)

    /// 渐变背景
    private static let gradientTop = Color(red: 0.97, green: 0.98, blue: 0.99)
    private static let gradientBottom = Color(red: 0.91, green: 0.93, blue: 0.97)

    static let secondaryText = Color.secondary

    static func gradientBackground() -> LinearGradient {
        LinearGradient(
            colors: [gradientTop, gradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 按分组返回图标，让残留清单一眼可读
    static func icon(for group: String) -> String {
        switch group {
        case "应用与副本": return "shippingbox"
        case "系统注册": return "keyboard"
        case "偏好设置": return "gearshape"
        case "钥匙串": return "key"
        case "用户数据": return "externaldrive"
        case "日志与缓存": return "doc.text"
        default: return "folder"
        }
    }
}

// MARK: - 主按钮样式

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    var pressedColor: Color = Theme.accentPressed

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? pressedColor : color)
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.15 : 0.3),
                    radius: configuration.isPressed ? 4 : 8, y: configuration.isPressed ? 2 : 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 圆形图标徽章

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
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(symbolColor)
        }
    }
}
