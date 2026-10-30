import StarSIRouter
import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(app.bubbles) { bubble in
                            BubbleView(bubble: bubble)
                                .id(bubble.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: app.bubbles.last?.text) {
                    if let last = app.bubbles.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("StarSI")
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            if app.voiceActive {
                Text(app.voiceStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                Button {
                    Task { await app.toggleVoice() }
                } label: {
                    Image(systemName: app.voiceActive ? "waveform.circle.fill" : "mic.circle")
                        .font(.title)
                        .foregroundStyle(app.voiceActive ? Color.accentColor : .secondary)
                }
                Button {
                    let text = draft
                    draft = ""
                    Task { await app.send(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(app.isStreaming
                          || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct BubbleView: View {
    let bubble: ChatBubble

    var body: some View {
        VStack(alignment: bubble.role == "user" ? .trailing : .leading, spacing: 4) {
            Text(bubble.text.isEmpty && !bubble.failed ? "…" : bubble.text)
                .padding(12)
                .background(
                    bubble.role == "user" ? Color.accentColor.opacity(0.9)
                        : bubble.failed ? Color.red.opacity(0.15)
                        : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(bubble.role == "user" ? .white : .primary)

            if bubble.role == "assistant", let target = bubble.servedBy {
                HStack(spacing: 4) {
                    Image(systemName: icon(for: target))
                    Text(target.displayName)
                    if let ms = bubble.firstTokenMs {
                        Text("· \(ms) ms")
                    }
                    if bubble.isWakingGPU {
                        Text("· waking GPU…")
                            .foregroundStyle(.blue)
                    }
                    if bubble.isOfflineFallback {
                        Text("· offline answer")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if bubble.isVoice {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity,
               alignment: bubble.role == "user" ? .trailing : .leading)
    }

    private func icon(for target: TargetID) -> String {
        switch target {
        case .iphone: "iphone"
        case .awsCPU: "cloud"
        case .awsGPU: "cloud.bolt"
        }
    }
}
