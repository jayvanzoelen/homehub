import SwiftUI

struct SetupView: View {
    @ObservedObject var settings: HubSettings
    let allowsCancel: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?

    init(settings: HubSettings, allowsCancel: Bool) {
        self.settings = settings
        self.allowsCancel = allowsCancel
        _address = State(
            initialValue: settings.serverURL?.absoluteString ?? HubAddress.suggestedAddress
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.accentColor)
                        Text("Connect this iPad to Home Hub")
                            .font(.title2.bold())
                        Text(
                            "Home Hub runs on another computer on your Wi-Fi. "
                                + "Enter that computer’s local address."
                        )
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                }

                Section("Server address") {
                    TextField("http://192.168.1.10:8787", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))

                    Text("The default Home Hub port is 8787.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        connectionTask?.cancel()
                        connectionTask = Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                            }
                            Text(isConnecting ? "Connecting…" : "Connect")
                                .font(.headline)
                            Spacer()
                        }
                        .frame(minHeight: 42)
                    }
                    .disabled(isConnecting)
                } footer: {
                    Text(
                        "Use plain HTTP only on a Wi-Fi network you trust. "
                            + "The app never sends your server address to a third party."
                    )
                }
            }
            .navigationTitle(allowsCancel ? "Server Settings" : "Home Hub Setup")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!allowsCancel)
            .toolbar {
                if allowsCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onDisappear {
            connectionTask?.cancel()
        }
    }

    @MainActor
    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            let serverURL = try HubAddress.normalize(address)
            let status = try await HubAPIClient(baseURL: serverURL).status()
            try Task.checkCancellation()
            if status.household.isEmpty {
                errorMessage = "The server did not identify itself as Home Hub."
                return
            }
            settings.save(serverURL: serverURL)
            address = serverURL.absoluteString
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
