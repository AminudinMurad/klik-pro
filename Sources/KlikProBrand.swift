import AppKit

/// One shared Klik PRO wordmark used by every app surface. Keeping the typography,
/// green, padding, and vertical offset here prevents the PRO pill from drifting
/// between onboarding, Settings, Mappings, and About.
enum KlikProBrand {
    static let titleFont = NSFont.systemFont(ofSize: 21, weight: .bold)
    // Keep the badge compact and raised beside the wordmark, like a product tier
    // marker rather than a second word at the same visual weight as "Klik".
    static let badgeFont = NSFont.systemFont(ofSize: 5, weight: .bold)
    static let badgeHeight: CGFloat = 8
    static let badgeHorizontalPadding: CGFloat = 2
    static let badgeCornerRadius: CGFloat = 1.5
    static let wordmarkGap: CGFloat = 3
    static let badgeRaise: CGFloat = 4
    static let green = NSColor(
        srgbRed: 25 / 255,
        green: 187 / 255,
        blue: 19 / 255,
        alpha: 1
    )

    static func wordmarkSize(prefix: String, scale: CGFloat = 1) -> NSSize {
        let title = "\(prefix)Klik" as NSString
        let badge = "PRO" as NSString
        let scaledTitleFont = NSFont.systemFont(
            ofSize: titleFont.pointSize * scale,
            weight: .bold
        )
        let scaledBadgeFont = NSFont.systemFont(
            ofSize: badgeFont.pointSize * scale,
            weight: .bold
        )
        let titleSize = title.size(withAttributes: [.font: scaledTitleFont])
        let badgeTextSize = badge.size(withAttributes: [.font: scaledBadgeFont])
        return NSSize(
            width: titleSize.width + wordmarkGap * scale
                + badgeTextSize.width + badgeHorizontalPadding * scale,
            height: max(titleSize.height, (badgeHeight + badgeRaise) * scale)
        )
    }
}

final class KlikProWordmarkView: NSView {
    private let prefix: String
    private let centered: Bool
    private let scale: CGFloat

    init(prefix: String = "", centered: Bool, scale: CGFloat = 1, frame: NSRect) {
        self.prefix = prefix
        self.centered = centered
        self.scale = scale
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(prefix)Klik PRO")
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let darkMode = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let titleColor = darkMode
            ? NSColor.white
            : NSColor(calibratedWhite: 0.13, alpha: 1)
        let titleFont = NSFont.systemFont(
            ofSize: KlikProBrand.titleFont.pointSize * scale,
            weight: .bold
        )
        let badgeFont = NSFont.systemFont(
            ofSize: KlikProBrand.badgeFont.pointSize * scale,
            weight: .bold
        )
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
        ]
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor.white,
        ]
        let title = "\(prefix)Klik" as NSString
        let badge = "PRO" as NSString
        let titleSize = title.size(withAttributes: titleAttributes)
        let badgeTextSize = badge.size(withAttributes: badgeAttributes)
        let contentSize = KlikProBrand.wordmarkSize(prefix: prefix, scale: scale)
        let startX = centered ? bounds.midX - contentSize.width / 2 : bounds.minX

        title.draw(
            at: NSPoint(x: startX, y: bounds.midY - titleSize.height / 2),
            withAttributes: titleAttributes
        )

        let badgeRect = NSRect(
            x: startX + titleSize.width + KlikProBrand.wordmarkGap * scale,
            y: bounds.midY - KlikProBrand.badgeHeight * scale / 2
                + KlikProBrand.badgeRaise * scale,
            width: badgeTextSize.width + KlikProBrand.badgeHorizontalPadding * scale,
            height: KlikProBrand.badgeHeight * scale
        )
        KlikProBrand.green.setFill()
        NSBezierPath(
            roundedRect: badgeRect,
            xRadius: KlikProBrand.badgeCornerRadius * scale,
            yRadius: KlikProBrand.badgeCornerRadius * scale
        ).fill()
        badge.draw(
            at: NSPoint(
                x: badgeRect.midX - badgeTextSize.width / 2,
                y: badgeRect.midY - badgeTextSize.height / 2
            ),
            withAttributes: badgeAttributes
        )
    }
}

private final class KlikProAboutLinkButton: NSButton {
    private let url: URL

    init(title: String, url: URL, frame: NSRect) {
        self.url = url
        super.init(frame: frame)
        isBordered = false
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        target = self
        action = #selector(openLink)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func openLink() {
        NSWorkspace.shared.open(url)
    }
}

final class KlikProAboutContentView: NSView {
    override var isFlipped: Bool { true }

    init(version: String, build: String) {
        let width: CGFloat = 380
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 162))

        let wordmark = KlikProWordmarkView(
            centered: true,
            frame: NSRect(x: 0, y: 0, width: width, height: 30)
        )

        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.frame = NSRect(x: 0, y: 38, width: width, height: 20)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: "Open-source mouse shortcuts and App Profiles for macOS, with thumb-wheel tab switching."
        )
        descriptionLabel.frame = NSRect(x: 30, y: 66, width: width - 60, height: 36)
        descriptionLabel.alignment = .center
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .labelColor
        descriptionLabel.maximumNumberOfLines = 2

        let copyright = NSTextField(labelWithString: "© 2026 Aminudin Murad · GPL-3.0")
        copyright.frame = NSRect(x: 0, y: 106, width: width, height: 16)
        copyright.alignment = .center
        copyright.font = .systemFont(ofSize: 11)
        copyright.textColor = .secondaryLabelColor

        let github = KlikProAboutLinkButton(
            title: "GitHub",
            url: URL(string: "https://github.com/AminudinMurad/klik-pro")!,
            frame: NSRect(x: 55, y: 136, width: 58, height: 20)
        )
        let license = KlikProAboutLinkButton(
            title: "GPL-3.0 License",
            url: URL(string: "https://github.com/AminudinMurad/klik-pro/blob/main/LICENSE")!,
            frame: NSRect(x: 139, y: 136, width: 78, height: 20)
        )
        let support = KlikProAboutLinkButton(
            title: "Support",
            url: URL(string: "https://github.com/sponsors/aminudinmurad")!,
            frame: NSRect(x: 243, y: 136, width: 108, height: 20)
        )
        for separatorX in [126, 230] as [CGFloat] {
            let separator = NSTextField(labelWithString: "•")
            separator.frame = NSRect(x: separatorX, y: 136, width: 10, height: 20)
            separator.alignment = .center
            separator.textColor = .secondaryLabelColor
            addSubview(separator)
        }

        [wordmark, versionLabel, descriptionLabel, copyright, github, license, support].forEach {
            addSubview($0)
        }
    }

    required init?(coder: NSCoder) { nil }
}

func makeKlikProAboutAlert(version: String, build: String, icon: NSImage) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .informational
    let displayIcon = (icon.copy() as? NSImage) ?? icon
    displayIcon.size = NSSize(width: 64, height: 64)
    alert.icon = displayIcon
    alert.messageText = ""
    alert.informativeText = ""
    alert.accessoryView = KlikProAboutContentView(version: version, build: build)
    alert.addButton(withTitle: "Close")
    return alert
}
