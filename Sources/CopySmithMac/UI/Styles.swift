import AppKit

enum Styles {

    // MARK: Colors

    static let appBackground     = NSColor(hex: "#FFFFFF")
    static let outerBorder       = NSColor(hex: "#005fa3")
    static let accentBlue        = NSColor(hex: "#0B5CAD")
    static let panelBackground   = NSColor(hex: "#F7FAFF")
    static let panelHover        = NSColor(hex: "#EAF3FF")
    static let buttonBackground  = NSColor(hex: "#F0F0F0")
    static let buttonHover       = NSColor(hex: "#E6E6E6")
    static let buttonBorder      = NSColor(hex: "#C6C6C6")
    static let textAreaBorder    = NSColor(hex: "#E0E0E0")
    static let primaryText       = NSColor(hex: "#333333")
    static let hintText          = NSColor(hex: "#888888")
    static let supportingText    = NSColor(hex: "#666666")
    static let errorText         = NSColor(hex: "#e74c3c")

    // MARK: Typography

    /// The preferred font. Falls back to system monospace if unavailable.
    static func font(size: CGFloat) -> NSFont {
        if let f = NSFont(name: "FantasqueSansMono-Regular", size: size) { return f }
        if let f = NSFont(name: "FantasqueSansM Nerd Font Mono", size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static let mainFontSize: CGFloat   = 18
    static let buttonFontSize: CGFloat = 14

    // MARK: Spacing

    static let windowWidth:  CGFloat = 1250
    static let windowHeight: CGFloat = 700

    static let rootMargin:        CGFloat = 8
    static let outerCornerRadius: CGFloat = 6
    static let outerBorderWidth:  CGFloat = 2

    static let combineWidth:      CGFloat = 350
    static let mainSpacing:       CGFloat = 6

    // Panel
    static let panelInnerMargin:   CGFloat = 6
    static let panelInternalSpacing: CGFloat = 4
    static let panelCollapsedHeight: CGFloat = 150
    static let panelExpandedHeight:  CGFloat = 400
    static let panelCornerRadius:    CGFloat = 4

    // Panel buttons
    static let refreshButtonWidth: CGFloat = 80
    static let copyButtonWidth:    CGFloat = 70
    static let addButtonWidth:     CGFloat = 85
    static let progressHeight:     CGFloat = 4

    // Combine panel
    static let combineInnerMargin:   CGFloat = 8
    static let combineSpacing:       CGFloat = 6
    static let selectedScrollMinH:   CGFloat = 60
    static let selectedScrollMaxH:   CGFloat = 120
}

// MARK: - NSColor hex init

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.hasPrefix("#") ? String(s.dropFirst()) : s
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255
        let b = CGFloat( rgb        & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
