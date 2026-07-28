import SwiftUI

struct GuardView: View {
    let baseURL: URL

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = MotionCameraController()
    @State private var armed = false
    @State private var threshold = 28.0
    @State private var cooldown = 8.0
    @State private var pin = ""
    @State private var events: [SecurityEventItem] = []
    @State private var isChangingArmState = false
    @State private var isVisible = false
    @State private var statusText = "Connecting to Home Hub…"
    @State private var isError = false

    private var client: HubAPIClient {
        HubAPIClient(baseURL: baseURL)
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width >= 850 {
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView {
                            guardPanel
                        }
                        .frame(maxWidth: .infinity)
                        ScrollView {
                            eventList
                        }
                        .frame(width: min(390, geometry.size.width * 0.42))
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            guardPanel
                            eventList
                        }
                        .padding(20)
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            camera.onMotion { jpeg in
                Task { await saveMotion(jpeg) }
            }
            await refresh()
        }
        .onAppear {
            isVisible = true
            camera.start()
        }
        .onDisappear {
            isVisible = false
            camera.configureDetection(armed: false, threshold: threshold, cooldown: cooldown)
            camera.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && isVisible {
                camera.start()
                camera.configureDetection(
                    armed: armed,
                    threshold: threshold,
                    cooldown: cooldown
                )
            } else {
                camera.configureDetection(armed: false, threshold: threshold, cooldown: cooldown)
                camera.stop()
            }
        }
    }

    private var guardPanel: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                Color.black
                CameraPreview(
                    session: camera.session,
                    mirrored: true,
                    onOrientationChange: camera.setVideoOrientation
                )

                Text(armed ? "ARMED" : "PREVIEW")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(armed ? Color.red.opacity(0.9) : Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(14)

                if !camera.isRunning && !camera.permissionDenied {
                    ProgressView("Starting camera…")
                        .tint(.white)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if camera.permissionDenied {
                permissionMessage
            } else if let cameraError = camera.errorMessage {
                Label(cameraError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Motion")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(camera.motionScore, specifier: "%.1f")%")
                        .font(.system(.subheadline, design: .monospaced))
                }
                ProgressView(value: min(camera.motionScore, 100), total: 100)
                    .tint(camera.motionScore >= threshold ? .red : .green)
                Text("Trigger threshold: \(threshold, specifier: "%.0f")%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SecureField("Household PIN (if configured)", text: $pin)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await changeArmState() }
            } label: {
                HStack {
                    if isChangingArmState {
                        ProgressView()
                            .tint(.white)
                    }
                    Label(
                        isChangingArmState ? "Updating…" : (armed ? "Disarm guard" : "Arm guard"),
                        systemImage: armed ? "lock.open.fill" : "lock.fill"
                    )
                    .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(armed ? .gray : .red)
            .controlSize(.large)
            .disabled(isChangingArmState || (!armed && !camera.isRunning))

            Text(statusText)
                .font(.headline)
                .foregroundColor(isError ? .red : (armed ? .red : .secondary))
                .multilineTextAlignment(.center)

            Text("Motion detection runs only while Guard is open in the foreground.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent activity")
                    .font(.title2.bold())
                Spacer()
                Button {
                    Task { await loadEvents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh activity")
            }

            if events.isEmpty {
                Text("No security events yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func eventRow(_ event: SecurityEventItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = client.mediaURL(for: event.snapshotURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black.opacity(0.08)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                    }
                }
                .frame(width: 92, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: icon(for: event.kind))
                    .font(.title2)
                    .foregroundColor(event.kind == "motion" ? .red : .secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(event.note)
                    .font(.headline)
                Text(event.displayDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var permissionMessage: some View {
        VStack(spacing: 10) {
            Text("Camera access is required for motion detection.")
                .multilineTextAlignment(.center)
            Button("Open iPad Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func refresh() async {
        do {
            let status = try await client.status()
            armed = status.armed
            threshold = status.motionThreshold
            cooldown = status.cooldownSeconds
            camera.configureDetection(
                armed: armed,
                threshold: threshold,
                cooldown: cooldown
            )
            isError = false
            statusText = armed ? "Watching for motion" : "Preview only — guard is disarmed"
        } catch {
            isError = true
            statusText = error.localizedDescription
        }
        await loadEvents()
    }

    @MainActor
    private func loadEvents() async {
        do {
            events = try await client.securityEvents()
        } catch {
            if events.isEmpty {
                isError = true
                statusText = error.localizedDescription
            }
        }
    }

    @MainActor
    private func changeArmState() async {
        isChangingArmState = true
        defer { isChangingArmState = false }
        do {
            let response = try await client.setArmed(!armed, pin: pin)
            armed = response.armed
            pin = ""
            camera.configureDetection(
                armed: armed,
                threshold: threshold,
                cooldown: cooldown
            )
            isError = false
            statusText = armed ? "Watching for motion" : "Preview only — guard is disarmed"
            await loadEvents()
        } catch {
            isError = true
            statusText = error.localizedDescription
        }
    }

    @MainActor
    private func saveMotion(_ jpeg: Data) async {
        guard armed else { return }
        statusText = "Motion detected — saving snapshot…"
        do {
            let response = try await client.uploadMotion(jpegData: jpeg)
            if response.ok {
                isError = false
                statusText = "Motion snapshot saved"
                await loadEvents()
            } else if response.ignored == true {
                statusText = "Watching for motion"
            }
        } catch {
            isError = true
            statusText = "Motion upload failed: \(error.localizedDescription)"
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "armed":
            return "lock.fill"
        case "disarmed":
            return "lock.open.fill"
        default:
            return "figure.walk"
        }
    }
}
