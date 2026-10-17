import SwiftUI

@main
struct ScooterLinkApp: App {
    @StateObject private var client = SABClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var client: SABClient
    @State private var tab = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                Picker("", selection: $tab) {
                    Text("Ride").tag(3)
                    Text("Buttons").tag(0)
                    Text("Devices").tag(1)
                    Text("Log").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch tab {
                case 3: RideView(client: client)
                case 0: ButtonsView()
                case 1: DevicesView(onConnect: { tab = 3 })
                default: LogView()
                }
            }
            .navigationTitle("ScooterLink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reconnect last scooter", systemImage: "arrow.clockwise") { client.reconnectLast() }
                        Button("Ask dash for phone screen", systemImage: "iphone") { client.requestPhoneScreen() }
                        Toggle("Register colours at connect", isOn: $client.registerColors)
                        Divider()
                        Button("Disconnect", systemImage: "xmark.circle") { client.disconnect() }
                        Button("Forget scooter key", systemImage: "key.slash", role: .destructive) { client.forgetKey() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.phase.rawValue).font(.headline)
                if let name = client.connectedName { Text(name).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding()
    }

    private var statusColor: Color {
        switch client.phase {
        case .ready: return .green
        case .failed: return .red
        case .idle: return .gray
        default: return .orange
        }
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
