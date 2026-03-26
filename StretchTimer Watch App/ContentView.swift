import SwiftUI
import UserNotifications

private enum OnboardingChoice {
    case alertsOnly
    case healthKit
}

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @State private var hasTouchedSettings = false
    @State private var appliedRecommendedDefaults = false
    @State private var crownDetent: Int = 0
    @State private var isCrownAccessoryVisible = false
    @FocusState private var crownFocused: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var showNotificationsExplainer = false
    @State private var pendingChoice: OnboardingChoice? = nil
    @State private var healthKitErrorMessage: String?

    private let minVolume: Double = 0.1
    private let maxVolume: Double = 1.0
    private let volumeStep: Double = 0.05

    var body: some View {
        if viewModel.isCompletingOnboarding {
            onboardingProgressScreen
        } else if viewModel.needsOnboarding {
            welcomeScreen
        } else {
            mainScreen
                .onAppear {
                    if !appliedRecommendedDefaults && !viewModel.isRunning {
                        viewModel.updateHoldSeconds(20)
                        viewModel.updateShiftSeconds(10)
                        appliedRecommendedDefaults = true
                    }
                }
        }
    }

    private var onboardingProgressScreen: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Setting up StretchTimer")
                .font(.headline)
            Text("Finishing permissions and saving your choice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }

    private var welcomeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose your setup")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 2)

                // Enable HealthKit option
                VStack(alignment: .leading, spacing: 6) {
                    Button("Enable HealthKit") {
                        pendingChoice = .healthKit
                        showNotificationsExplainer = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Enable HealthKit")
                    .accessibilityHint("Enable background running and Smart Stack using workout permission only.")

                    Text("…only to run in background and Smart Stack. No health data read/write.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Alerts Only option
                VStack(alignment: .leading, spacing: 6) {
                    Button("Alerts Only") {
                        pendingChoice = .alertsOnly
                        showNotificationsExplainer = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Alerts Only")
                    .accessibilityHint("Use the app without HealthKit. You can enable it later.")

                    Text("Use the app without HealthKit. You can turn it on later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showNotificationsExplainer) {
            NotificationsExplainerView(
                onAllow: {
                    requestNotificationAuthorization { _ in
                        proceedAfterExplainer()
                    }
                },
                onNotNow: {
                    proceedAfterExplainer()
                }
            )
        }
        .alert("HealthKit Permission Needed", isPresented: healthKitAlertPresented) {
            Button("OK", role: .cancel) {
                healthKitErrorMessage = nil
            }
        } message: {
            Text(healthKitErrorMessage ?? "Workout permission is required for background sessions.")
        }
    }

    private var mainScreen: some View {
        VStack(spacing: 10) {
            crownHost
            if !shouldHideControlsForReducedLuminance && !viewModel.isPreparingStart {
                settingsPanel
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear {
            syncCrownValue()
            viewModel.updateDisplayDimmed(isLuminanceReduced)
        }
        .onChange(of: viewModel.isRunning) { _, _ in
            syncCrownValue()
            isCrownAccessoryVisible = false
        }
        .onChange(of: isLuminanceReduced) { _, _ in
            viewModel.updateDisplayDimmed(isLuminanceReduced)
        }
        .onChange(of: viewModel.totalDurationSeconds) { _, _ in
            if !viewModel.isRunning {
                syncCrownValue()
            }
        }
        .onChange(of: viewModel.sessionVolume) { _, _ in
            if viewModel.isRunning {
                syncCrownValue()
            }
        }
    }

    private var crownHost: some View {
        timerActionButton
            .contentShape(Rectangle())
            .focusable(true)
            .focused($crownFocused)
            .digitalCrownRotation(
                detent: $crownDetent,
                from: 0,
                through: viewModel.isRunning ? maxVolumeSteps : maxDurationSteps,
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            ) { _ in
                isCrownAccessoryVisible = viewModel.isRunning
                if viewModel.isRunning {
                    let volume = minVolume + (Double(crownDetent) * volumeStep)
                    viewModel.updateSessionVolume(Float(clamp(volume, minVolume, maxVolume)))
                } else {
                    let seconds = TimerViewModel.minTotalSeconds + crownDetent * TimerViewModel.totalStepSeconds
                    viewModel.updateTotalDurationSeconds(clamp(seconds, TimerViewModel.minTotalSeconds, TimerViewModel.maxTotalSeconds))
                }
            } onIdle: {
                isCrownAccessoryVisible = false
                syncCrownValue()
            }
            .digitalCrownAccessory {
                if viewModel.isRunning && isCrownAccessoryVisible {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                }
            }
            .onAppear {
                crownFocused = true
            }
            .onTapGesture {
                crownFocused = true
            }
    }

    @ViewBuilder
    private var timerActionButton: some View {
        if viewModel.isRunning && isLuminanceReduced {
            TimelineView(ExplicitTimelineSchedule(viewModel.dimmedTimelineDates)) { context in
                timerButton(displayDate: context.date)
            }
        } else {
            timerButton(displayDate: nil)
        }
    }

    private func timerButton(displayDate: Date?) -> some View {
        Button {
            if viewModel.isRunning || viewModel.isPreparingStart {
                viewModel.stop()
            } else {
                viewModel.start()
            }
        } label: {
            timerButtonLabel(displayDate: displayDate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(timerButtonColor)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(timerButtonColor.opacity(0.14))
        )
        .overlay(timerButtonOverlay(displayDate: displayDate))
    }

    @ViewBuilder
    private func timerButtonLabel(displayDate: Date?) -> some View {
        if viewModel.isPreparingStart {
            VStack(spacing: 4) {
                Text("\(viewModel.startCountdownValue)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("GET READY")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        } else
        if let displayDate, viewModel.isRunning && isLuminanceReduced {
            VStack(spacing: 4) {
                Spacer(minLength: 12)
                Text(dimmedPhaseLabel(at: displayDate))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer(minLength: 12)
            }
        } else {
            VStack(spacing: 4) {
                Text(formatted(seconds: viewModel.isRunning ? viewModel.remainingSeconds : viewModel.totalDisplaySeconds))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if viewModel.isRunning {
                    Text(viewModel.currentPhase == .hold ? "HOLD" : "SHIFT")
                        .font(.caption)
                        .fontWeight(.semibold)
                } else {
                    Text("START")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func timerButtonOverlay(displayDate: Date?) -> some View {
        if viewModel.isRunning {
            let progress = progressForDisplay(at: displayDate)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.red, lineWidth: 6)
                ProgressRoundedRect(progress: progress, cornerRadius: 18)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .animation(isLuminanceReduced ? nil : .linear(duration: 0.2), value: progress)
            }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(timerButtonColor, lineWidth: 6)
        }
    }

    private var timerButtonColor: Color {
        if viewModel.isPreparingStart {
            return .orange
        }
        return viewModel.isRunning ? .red : .green
    }

    private var settingsPanel: some View {
        ZStack {
            VStack(spacing: 8) {
                durationRow(
                    title: "Hold",
                    value: viewModel.holdSeconds,
                    decrement: viewModel.decrementHold,
                    increment: viewModel.incrementHold
                )

                durationRow(
                    title: "Shift",
                    value: viewModel.shiftSeconds,
                    decrement: viewModel.decrementShift,
                    increment: viewModel.incrementShift
                )

                Toggle(viewModel.announcementsEnabled ? "Announce" : "Alert", isOn: announcementsBinding)
                    .font(.footnote)
                    .disabled(viewModel.isRunning)

            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if shouldShowRecommendationOverlay {
                VStack(spacing: 2) {
                    Text("Recommended Set")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("5 stretches 3x each")
                        .font(.caption2)
                    Text("Hold 20s+ shift 10s")
                        .font(.caption2)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !hasTouchedSettings && !viewModel.isRunning {
                viewModel.updateHoldSeconds(20)
                viewModel.updateShiftSeconds(10)
            }
            hasTouchedSettings = true
        }
    }

    private var shouldShowRecommendationOverlay: Bool {
        !hasTouchedSettings && !viewModel.isRunning
    }

    private var shouldHideControlsForReducedLuminance: Bool {
        viewModel.isRunning && isLuminanceReduced
    }

    private func durationRow(
        title: String,
        value: Int,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .frame(width: 42, alignment: .leading)

            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRunning || value <= TimerSettings.minSeconds)

            Text("\(value)s")
                .font(.headline)
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRunning || value >= TimerSettings.maxSeconds)
        }
    }

    private var announcementsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.announcementsEnabled },
            set: { viewModel.updateAnnouncementsEnabled($0) }
        )
    }

    private func syncCrownValue() {
        if viewModel.isRunning {
            let steps = ((Double(viewModel.sessionVolume) - minVolume) / volumeStep).rounded()
            crownDetent = clamp(Int(steps), 0, maxVolumeSteps)
        } else {
            let steps = (viewModel.totalDurationSeconds - TimerViewModel.minTotalSeconds) / TimerViewModel.totalStepSeconds
            crownDetent = clamp(steps, 0, maxDurationSteps)
        }
    }

    private var maxDurationSteps: Int {
        (TimerViewModel.maxTotalSeconds - TimerViewModel.minTotalSeconds) / TimerViewModel.totalStepSeconds
    }

    private var maxVolumeSteps: Int {
        Int(((maxVolume - minVolume) / volumeStep).rounded())
    }

    private func clamp<T: Comparable>(_ value: T, _ minValue: T, _ maxValue: T) -> T {
        min(max(value, minValue), maxValue)
    }

    private var elapsedFraction: CGFloat {
        let total = max(1, viewModel.totalDurationSeconds)
        let remaining = viewModel.totalRemainingSeconds
        let fraction = 1.0 - (Double(remaining) / Double(total))
        return CGFloat(max(0.0, min(1.0, fraction)))
    }

    private func progressForDisplay(at displayDate: Date?) -> CGFloat {
        if let displayDate, isLuminanceReduced, viewModel.isRunning {
            return viewModel.elapsedFraction(at: displayDate)
        }
        return elapsedFraction
    }

    private func formatted(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func dimmedPhaseLabel(at date: Date) -> String {
        switch viewModel.phase(at: date) {
        case .hold:
            return "HOLD"
        case .shift:
            return "SHIFT"
        case .none:
            return viewModel.currentPhase == .hold ? "HOLD" : "SHIFT"
        }
    }

    private func requestNotificationAuthorization(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    private func proceedAfterExplainer() {
        let choice = pendingChoice
        pendingChoice = nil
        showNotificationsExplainer = false

        switch choice {
        case .alertsOnly:
            viewModel.beginOnboardingResolution()
            viewModel.selectBackgroundMode(.alertsOnly)
            viewModel.finishOnboardingResolution()
        case .healthKit:
            viewModel.beginOnboardingResolution()
            Task {
                defer { viewModel.finishOnboardingResolution() }
                do {
                    try await viewModel.enableHealthKitMode()
                } catch {
                    healthKitErrorMessage = error.localizedDescription
                }
            }
        case .none:
            break
        }
    }

    private var healthKitAlertPresented: Binding<Bool> {
        Binding(
            get: { healthKitErrorMessage != nil },
            set: { if !$0 { healthKitErrorMessage = nil } }
        )
    }
}

private struct NotificationsExplainerView: View {
    var onAllow: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enable Alerts")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Text("...for interval timer sounds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Allow Alerts", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Not now", action: onNotNow)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
    }
}

private struct ProgressRoundedRect: Shape {
    var progress: CGFloat
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let topCenter = CGPoint(x: rect.midX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - r, y: rect.minY)
        let rightTop = CGPoint(x: rect.maxX, y: rect.minY + r)
        let bottomRight = CGPoint(x: rect.maxX - r, y: rect.maxY)
        let leftBottom = CGPoint(x: rect.minX, y: rect.maxY - r)
        let topLeft = CGPoint(x: rect.minX + r, y: rect.minY)
        let topCenterLeft = CGPoint(x: rect.midX - r, y: rect.minY)

        let arcLength = CGFloat.pi / 2 * r
        let topHalf = rect.width / 2 - r
        let rightSide = rect.height - 2 * r
        let bottomSide = rect.width - 2 * r
        let leftSide = rect.height - 2 * r
        let total = topHalf + arcLength + rightSide + arcLength + bottomSide + arcLength + leftSide + arcLength + topHalf

        var remaining = max(0, min(1, progress)) * total
        var path = Path()
        path.move(to: topCenter)

        func addLine(to point: CGPoint, length: CGFloat) {
            guard remaining > 0 else { return }
            let use = min(remaining, length)
            let t = use / length
            let x = topCenter.x + (point.x - topCenter.x) * t
            let y = topCenter.y + (point.y - topCenter.y) * t
            path.addLine(to: CGPoint(x: x, y: y))
            remaining -= use
        }

        // Top right half
        addLine(to: topRight, length: topHalf)
        if remaining <= 0 { return path }

        // Top-right arc
        let arcUse = min(remaining, arcLength)
        let arcAngle = arcUse / arcLength * CGFloat.pi / 2
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + Double(arcAngle * 180 / .pi)),
                    clockwise: false)
        remaining -= arcUse
        if remaining <= 0 { return path }

        // Right side
        let rightUse = min(remaining, rightSide)
        path.addLine(to: CGPoint(x: rect.maxX, y: rightTop.y + rightUse))
        remaining -= rightUse
        if remaining <= 0 { return path }

        // Bottom-right arc
        let arcUse2 = min(remaining, arcLength)
        let arcAngle2 = arcUse2 / arcLength * CGFloat.pi / 2
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r,
                    startAngle: .degrees(0),
                    endAngle: .degrees(Double(arcAngle2 * 180 / .pi)),
                    clockwise: false)
        remaining -= arcUse2
        if remaining <= 0 { return path }

        // Bottom side
        let bottomUse = min(remaining, bottomSide)
        path.addLine(to: CGPoint(x: bottomRight.x - bottomUse, y: rect.maxY))
        remaining -= bottomUse
        if remaining <= 0 { return path }

        // Bottom-left arc
        let arcUse3 = min(remaining, arcLength)
        let arcAngle3 = arcUse3 / arcLength * CGFloat.pi / 2
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                    radius: r,
                    startAngle: .degrees(90),
                    endAngle: .degrees(90 + Double(arcAngle3 * 180 / .pi)),
                    clockwise: false)
        remaining -= arcUse3
        if remaining <= 0 { return path }

        // Left side
        let leftUse = min(remaining, leftSide)
        path.addLine(to: CGPoint(x: rect.minX, y: leftBottom.y - leftUse))
        remaining -= leftUse
        if remaining <= 0 { return path }

        // Top-left arc
        let arcUse4 = min(remaining, arcLength)
        let arcAngle4 = arcUse4 / arcLength * CGFloat.pi / 2
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                    radius: r,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 + Double(arcAngle4 * 180 / .pi)),
                    clockwise: false)
        remaining -= arcUse4
        if remaining <= 0 { return path }

        // Top left half to center
        let topLeftUse = min(remaining, topHalf)
        let t = topLeftUse / topHalf
        let x = topLeft.x + (topCenterLeft.x - topLeft.x) * t
        let y = rect.minY
        path.addLine(to: CGPoint(x: x, y: y))
        return path
    }
}

#Preview {
    ContentView()
}
