import SwiftUI

@main
struct ScooterLinkApp: App {
    @StateObject private var client = SABClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var client: SABClient

    var body: some View {
        NavigationStack {
            HomeView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Reconnect", systemImage: "arrow.clockwise") { client.reconnectLast() }
                            Button("Show phone screen on dash", systemImage: "iphone.gen3") { client.ensurePhoneScreen() }
                            Divider()
                            Button("Disconnect", systemImage: "xmark.circle") { client.disconnect() }
                            Button("Forget scooter key", systemImage: "key.slash", role: .destructive) { client.forgetKey() }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

/// Scanning, raw button events and the protocol log, for when something needs looking into.
struct DiagnosticsView: View {
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Devices").tag(0)
                Text("Buttons").tag(1)
                Text("Log").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            switch tab {
            case 0: DevicesView(onConnect: { tab = 1 })
            case 1: ButtonsView()
            default: LogView()
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ButtonsView: View {
    @EnvironmentObject private var client: SABClient

    var body: some View {
        VStack(spacing: 16) {
            if let last = client.presses.first {
                VStack(spacing: 8) {
                    Image(systemName: last.function?.symbol ?? "questionmark")
                        .font(.system(size: 64, weight: .semibold))
                    Text(last.function?.label ?? "Unknown 0x\(String(format: "%02X", last.raw))")
                        .font(.title.bold())
                    Text(last.time, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)
                .id(last.id)
                .transition(.scale.combined(with: .opacity))
            } else {
                ContentUnavailableView("No presses yet",
                                       systemImage: "hand.tap",
                                       description: Text("Connect in Devices, then press each handlebar button."))
            }

            List {
                Section("Seen so far") {
                    ForEach(ButtonFunction.allCases, id: \.rawValue) { function in
                        let count = client.presses.filter { $0.raw == function.rawValue }.count
                        HStack {
                            Image(systemName: function.symbol).frame(width: 28)
                            Text(function.label)
                            Spacer()
                            Text(count == 0 ? "—" : "×\(count)")
                                .foregroundStyle(count == 0 ? .secondary : .primary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.25), value: client.presses.first?.id)
    }
}

struct DevicesView: View {
    @EnvironmentObject private var client: SABClient
    let onConnect: () -> Void

    var body: some View {
        List {
            Section {
                if client.phase == .scanning {
                    Button("Stop scanning", systemImage: "stop.circle") { client.stopScan() }
                } else {
                    Button("Scan for scooter", systemImage: "dot.radiowaves.left.and.right") { client.startScan() }
                }
                Toggle("Show all Bluetooth devices", isOn: $client.showAllDevices)
            } footer: {
                Text("Before the first connect: delete the RoadSync phone pairing on the PCX dashboard, so the scooter accepts this app's key.")
            }
            Section("Found") {
                ForEach(client.devices.filter { client.showAllDevices || $0.isHonda }) { device in
                    Button {
                        client.connect(device)
                        onConnect()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text(device.id.uuidString.prefix(8)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if device.isHonda { Text("Honda").font(.caption.bold()).foregroundStyle(.red) }
                            if device.rssi != 0 { Text("\(device.rssi) dBm").font(.caption).monospacedDigit() }
                        }
                    }
                }
            }
        }
    }
}

struct LogView: View {
    @EnvironmentObject private var client: SABClient

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ShareLink(item: client.logText) { Label("Share log", systemImage: "square.and.arrow.up") }
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = client.logText }
                Button("Clear", systemImage: "trash", role: .destructive) { client.clearLog() }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
            ScrollViewReader { proxy in
                List(client.log) { line in
                    Text(line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(line.isError ? .red : .primary)
                        .id(line.id)
                }
                .listStyle(.plain)
                .onChange(of: client.log.count) { _, _ in
                    if let last = client.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}
