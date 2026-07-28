import SwiftUI

struct ScanView: View {
    let baseURL: URL

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = ScanCameraController()
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "ea"
    @State private var location = InventoryLocation.pantry
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var requestSuggestion = false
    @State private var visionEnabled = false
    @State private var pendingPhotoPath: String?
    @State private var isSaving = false
    @State private var isVisible = false
    @State private var message: String?
    @State private var isError = false

    private var client: HubAPIClient {
        HubAPIClient(baseURL: baseURL)
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 850 {
                    HStack(alignment: .top, spacing: 24) {
                        cameraPanel
                            .frame(maxWidth: .infinity)
                        if camera.capturedImage != nil {
                            detailsForm
                                .frame(width: min(390, geometry.size.width * 0.42))
                        }
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            cameraPanel
                            if camera.capturedImage != nil {
                                detailsForm
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await loadStatus()
        }
        .onAppear {
            isVisible = true
            camera.start()
        }
        .onDisappear {
            isVisible = false
            camera.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && isVisible {
                camera.start()
            } else {
                camera.stop()
            }
        }
    }

    private var cameraPanel: some View {
        VStack(spacing: 14) {
            ZStack {
                Color.black
                if let image = camera.capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    CameraPreview(
                        session: camera.session,
                        mirrored: camera.isFrontCamera,
                        onOrientationChange: camera.setVideoOrientation
                    )
                    if !camera.isRunning && !camera.permissionDenied {
                        ProgressView("Starting camera…")
                            .tint(.white)
                            .foregroundColor(.white)
                    }
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }

            if camera.permissionDenied {
                permissionMessage
            } else if let cameraError = camera.errorMessage {
                Label(cameraError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } else {
                cameraControls
            }

            if let message {
                Text(message)
                    .font(.headline)
                    .foregroundColor(isError ? .red : .green)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var cameraControls: some View {
        HStack(spacing: 14) {
            if camera.capturedImage == nil {
                Button(action: camera.capture) {
                    Label(
                        camera.isCapturing ? "Capturing…" : "Capture item",
                        systemImage: "camera.fill"
                    )
                        .frame(minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!camera.isRunning || camera.isCapturing || isSaving)

                Button(action: camera.flipCamera) {
                    Label("Flip", systemImage: "arrow.triangle.2.circlepath.camera")
                        .frame(minHeight: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!camera.isRunning || camera.isCapturing || isSaving)
            } else {
                Button {
                    pendingPhotoPath = nil
                    message = nil
                    camera.retake()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(minHeight: 34)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSaving)
            }
        }
    }

    private var detailsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Item details")
                .font(.title2.bold())

            field("Name") {
                TextField("Milk", text: $name)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                field("Quantity") {
                    TextField("1", text: $quantity)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                field("Unit") {
                    TextField("ea", text: $unit)
                        .textFieldStyle(.roundedBorder)
                }
            }

            field("Location") {
                Picker("Location", selection: $location) {
                    ForEach(InventoryLocation.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Use an expiry date", isOn: $hasExpiry)
            if hasExpiry {
                DatePicker(
                    "Expires",
                    selection: $expiry,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }

            if visionEnabled {
                Toggle("Suggest the name using vision", isOn: $requestSuggestion)
            }

            Button {
                Task { await saveItem() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSaving ? "Saving…" : "Save to pantry")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(isSaving)
    }

    private var permissionMessage: some View {
        VStack(spacing: 10) {
            Text("Camera access is required to scan pantry items.")
                .multilineTextAlignment(.center)
            Button("Open iPad Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadStatus() async {
        do {
            visionEnabled = try await client.status().visionEnabled
        } catch {
            // Scanning still works without the optional status metadata.
        }
    }

    @MainActor
    private func saveItem() async {
        guard let jpeg = camera.capturedJPEG else {
            show(error: "Capture a photo first.")
            return
        }
        guard let parsedQuantity = Double(quantity.replacingOccurrences(of: ",", with: ".")),
              parsedQuantity >= 0
        else {
            show(error: "Enter a valid quantity.")
            return
        }

        let details = ScanDetails(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: parsedQuantity,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "ea"
                : unit.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location,
            expiresOn: hasExpiry ? expiry : nil,
            requestSuggestion: requestSuggestion
        )
        if pendingPhotoPath != nil && details.name.isEmpty {
            show(error: "Name the item before saving.")
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let response: ScanResponse
            if let pendingPhotoPath {
                response = try await client.confirmScan(
                    photoPath: pendingPhotoPath,
                    details: details
                )
            } else {
                response = try await client.scan(jpegData: jpeg, details: details)
            }

            if response.needsName == true {
                pendingPhotoPath = response.photoPath
                if let suggestion = response.suggestedName, !suggestion.isEmpty {
                    name = suggestion
                }
                show(success: "Add or confirm the item name, then save again.")
            } else if response.ok {
                let savedName = response.name ?? details.name
                show(success: "Saved “\(savedName)” to the pantry.")
                pendingPhotoPath = nil
                name = ""
                quantity = "1"
                unit = "ea"
                hasExpiry = false
                requestSuggestion = false
                camera.retake()
            } else {
                show(error: "The item could not be saved.")
            }
        } catch {
            show(error: error.localizedDescription)
        }
    }

    private func show(success: String) {
        isError = false
        message = success
    }

    private func show(error: String) {
        isError = true
        message = error
    }
}
