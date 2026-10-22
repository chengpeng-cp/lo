import AppKit

// MARK: - 设计令牌
//
// 设置页与悬浮窗共用的视觉规范。参考 macOS 系统设置的分层结构：
// 侧边栏（毛玻璃）+ 内容区（卡片分组）+ 细边框与克制的强调色。

enum LODesign {

    // MARK: - 颜色

    enum Color {
        /// 侧边栏背景（配合 NSVisualEffectView 使用，这里仅作兜底）
        static var sidebar: NSColor { dynamic(light: 0.96, dark: 0.11) }

        /// 内容区背景
        static var content: NSColor { dynamic(light: 1.0, dark: 0.13) }

        /// 卡片背景
        static var card: NSColor { dynamic(light: 0.965, dark: 0.175) }

        /// 卡片悬停/内嵌控件背景
        static var cardElevated: NSColor { dynamic(light: 0.93, dark: 0.215) }

        /// 卡片边框（hairline）
        static var border: NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 1.0, alpha: 0.07)
                    : NSColor(white: 0.0, alpha: 0.06)
            }
        }

        /// 主文本
        static var textPrimary: NSColor { .labelColor }

        /// 次要文本（说明、单位）
        static var textSecondary: NSColor { .secondaryLabelColor }

        /// 三级文本（区块小标题）
        static var textTertiary: NSColor { .tertiaryLabelColor }

        /// 强调色
        static var accent: NSColor { .controlAccentColor }

        /// 选中项背景（侧边栏）
        static var sidebarSelection: NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor(white: 1.0, alpha: 0.10)
                    : NSColor(white: 0.0, alpha: 0.07)
            }
        }

        private static func dynamic(light: CGFloat, dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: dark, alpha: 1.0)
                    : NSColor(white: light, alpha: 1.0)
            }
        }
    }

    // MARK: - 字体

    enum Font {
        /// 页面标题
        static var pageTitle: NSFont { .systemFont(ofSize: 17, weight: .semibold) }
        /// 卡片内主行文字
        static var row: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 行内强调（开关标题）
        static var rowStrong: NSFont { .systemFont(ofSize: 13, weight: .medium) }
        /// 说明文字
        static var caption: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        /// 数值等宽显示
        static var mono: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }
    }

    // MARK: - 尺寸与间距

    enum Metric {
        static let sidebarWidth: CGFloat = 184
        static let sidebarInset: CGFloat = 10
        static let sidebarItemHeight: CGFloat = 32

        static let contentMargin: CGFloat = 22
        /// 内容区底部留白，比顶部略大，保证最后一行不会被滚动区边缘裁切
        static let contentBottomInset: CGFloat = 26
        static let cardCorner: CGFloat = 10
        static let cardPadding: CGFloat = 14
        static let cardGap: CGFloat = 18
        static let rowGap: CGFloat = 10
        static let labelGap: CGFloat = 12
        static let labelWidth: CGFloat = 92
        static let rowHeight: CGFloat = 24
        static let controlHeight: CGFloat = 24
    }
}

// MARK: - 便捷构造

extension NSTextField {
    /// 设置页统一风格的标签
    static func loLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
