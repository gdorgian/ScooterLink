import SwiftUI

/// What the dash shows right now, the ride numbers, and the colour theme.
struct RideView: View {
    @EnvironmentObject private var client: SABClient
    @ObservedObject private var ride: RideState
    @State private var pickedColor: Color

    init(client: SABClient) {
        _ride = ObservedObject(wrappedValue: client.ride)
        _pickedColor = State(initialValue: client.theme.color)
    }

    var body: some View {
        List {
            if Features.drawOnDash { Section("On the dash") {
                DashPreview(screen: client.dashScreen ?? ride.rideScreen(colors: client.screenColors),
                            theme: client.theme)
                    .listRowInsets(EdgeInsets())
                if client.phase != .ready {
                    Text("Connect to the scooter to show this on the dash.").font(.footnote).foregroundStyle(.secondary)
                }
            } }
            Section("Dash") {
                LabeledContent("Screen", value: client.dashMode.rawValue)
                LabeledContent("Audio", value: ride.isAudioPlaying ? "Playing" : "Paused")
                Button("Ask dash for phone screen", systemImage: "iphone") { client.ensurePhoneScreen() }
            }
            if Features.customColours { Section {
                ColorPicker("Dash colour", selection: $pickedColor, supportsOpacity: false)
                Button("Save colour", systemImage: "paintbrush") { client.applyTheme(Theme(pickedColor)) }
            } header: {
                Text("Theme")
            } footer: {
                Text("Applied the next time you turn the ignition on. Header and body use your colour, the text area a dark shade, the buttons a light shade.")
            } }
        }
    }
}

/// Rough phone-side preview of the dash LIVE layout.
struct DashPreview: View {
    let screen: LiveScreen
    let theme: Theme

    private func color(_ rgb: [UInt8]) -> Color {
        Color(red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255)
    }

    private func symbol(_ icon: UInt8?) -> String? {
        switch icon {
        case DashIcon.play: return "play.fill"
        case DashIcon.pause: return "pause.fill"
        case DashIcon.next: return "forward.fill"
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(screen.header)
                .font(.system(.subheadline, design: .monospaced).bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(color(theme.main))
            HStack(spacing: 8) {
                action(screen.leftAction)
                VStack(spacing: 4) {
                    Text(screen.line1 ?? "").font(.system(.title, design: .rounded).bold())
                    Text(screen.line2 ?? "").font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color(theme.dark), in: RoundedRectangle(cornerRadius: 6))
                action(screen.rightAction)
            }
            .padding(8)
            .background(color(theme.main))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private func action(_ icon: UInt8?) -> some View {
        if let name = symbol(icon) {
            Image(systemName: name)
                .frame(width: 40, height: 56)
                .background(color(theme.light), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
