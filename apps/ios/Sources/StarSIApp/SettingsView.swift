import StarSIRouter
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var copiedKey = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                TextField("Host or IP", text: $app.awsHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Pinned host key (ssh-ed25519 …)", text: $app.awsHostKey, axis: .vertical)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("GPU tier", isOn: $app.gpuEnabled)
            } header: {
                Text("AWS rendezvous (SSH)")
            } footer: {
                Text("Get the host key with: ssh-keyscan -t ed25519 <host>")
            }

            Section {
                Text(app.devicePublicKey)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                Button(copiedKey ? "Copied" : "Copy public key") {
                    UIPasteboard.general.string = app.devicePublicKey
                    copiedKey = true
                }
            } header: {
                Text("This phone's SSH key")
            } footer: {
                Text("Add it to infra/ssh/authorized_keys.d/aws and run "
                     + "distribute-authorized-keys.sh. The private key never leaves the phone.")
            }

            Section("Auth") {
                SecureField("Device token", text: $app.deviceToken)
            }

            Section("Routing") {
                Toggle("Allow private prompts over my own AWS",
                       isOn: $app.allowPrivateOverOwnCloud)
                Picker("Force target", selection: $app.forcedTarget) {
                    Text("Automatic").tag(TargetID?.none)
                    ForEach(TargetID.allCases) { id in
                        Text(id.displayName).tag(TargetID?.some(id))
                    }
                }
                NavigationLink("Routing log") { RoutingLogView() }
            }
        }
        .navigationTitle("Settings")
    }
}

struct RoutingLogView: View {
    @Environment(AppState.self) private var app
    @State private var entries: [RoutingLogEntry] = []

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.decision.target.displayName).bold()
                    Text(entry.decision.rule)
                    if entry.decision.requiresWake { Text("· waking GPU") }
                    Spacer()
                    if let ms = entry.firstTokenMs { Text("\(ms) ms") }
                }
                .font(.caption)
                Text("tunnel: \(entry.signals.tunnelUp ? "up" : "down") · tiers: \(entry.signals.tierHealthy.map(\.rawValue).sorted().joined(separator: ",")) · gpu: \(entry.signals.gpuState.rawValue) · net: \(entry.signals.network.rawValue) · \(entry.labels.reasoning.rawValue)/\(entry.labels.latencyTolerance.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.ts.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("Routing log")
        .task { entries = await app.log.recent() }
    }
}
