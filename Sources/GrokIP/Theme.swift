import CoreText
import SwiftUI

enum Palette {
    static let chassis = Color(red: 0.071, green: 0.102, blue: 0.141)
    static let panel = Color(red: 0.106, green: 0.153, blue: 0.204)
    static let well = Color(red: 0.047, green: 0.067, blue: 0.094)
    static let hairline = Color(red: 0.22, green: 0.30, blue: 0.38)
    static let keystone = Color(red: 0.906, green: 0.882, blue: 0.831)
    static let keystoneDim = Color(red: 0.55, green: 0.53, blue: 0.48)
    static let text = Color(red: 0.910, green: 0.933, blue: 0.961)
    static let muted = Color(red: 0.494, green: 0.565, blue: 0.651)
    static let linkLED = Color(red: 0.243, green: 0.776, blue: 1.0)
    static let activity = Color(red: 0.941, green: 0.706, blue: 0.161)
    static let pairOrange = Color(red: 0.902, green: 0.478, blue: 0.180)
    static let login = Color(red: 0.424, green: 0.722, blue: 1.0)
    static let stop = Color(red: 0.910, green: 0.365, blue: 0.298)
    static let live = Color(red: 0.369, green: 0.878, blue: 0.627)
    static let rowHover = Color(red: 0.133, green: 0.188, blue: 0.247)
    static let rowSelected = Color(red: 0.145, green: 0.227, blue: 0.310)
}

enum Typeface {
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("IBM Plex Sans", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("IBM Plex Mono", size: size).weight(weight)
    }
}

enum AppFonts {
    static func register() {
        let files = [
            "IBMPlexSans-Regular",
            "IBMPlexSans-Medium",
            "IBMPlexSans-SemiBold",
            "IBMPlexMono-Regular",
            "IBMPlexMono-Medium"
        ]
        for name in files {
            let url = ResourceLocator.url(name: name, ext: "ttf", subdirectory: "Fonts")
                ?? ResourceLocator.url(name: name, ext: "ttf")
            if let url {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

struct KeystoneButtonStyle: ButtonStyle {
    var emphasis: Bool = false
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.sans(13, weight: .medium))
            .foregroundStyle(destructive ? Palette.keystone : (emphasis ? Palette.chassis : Palette.text))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(destructive ? Palette.stop : (emphasis ? Palette.keystone : Palette.panel))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(destructive ? Palette.stop : (emphasis ? Palette.keystone : Palette.hairline), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct ServiceChip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Typeface.mono(10, weight: .medium))
            .foregroundStyle(Palette.keystone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Palette.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )
    }
}
