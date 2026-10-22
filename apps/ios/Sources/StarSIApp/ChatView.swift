import SwiftUI
import StarSIClient

struct ChatView: View {
    @State private var input = ""
    var body: some View {
        VStack {
            Spacer()
            Text("StarSI").font(.largeTitle)
            Text("No node connected").foregroundStyle(.secondary)
            Spacer()
            HStack {
                TextField("Say something", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {}.disabled(input.isEmpty)
            }
            .padding()
        }
    }
}
