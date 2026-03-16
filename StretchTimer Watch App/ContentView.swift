import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TimerViewModel()
    @State private var hasTouchedSettings = false
    @State private var appliedRecommendedDefaults = false
    @State private var reducedProgress: CGFloat = 0
    @State private var crownDetent: Double = 0
    @FocusState private var crownFocused: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private let minVolume: Double = 0.1
    private let maxVolume: Double = 1.0
    private let volumeStep: Double = 0.05

    var body: some View {
        if viewModel.needsOnboarding {
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

    private var welcomeScreen: some View {
        VStack(spacing: 12) {
            Text("Alerts Only for countdown & sound on idle/off display.")
                .font(.footnote)
                .multilineTextAlignment(.center)

            Text("Smart Stack & Alerts = HealthKit No read/write.")
                .font(.footnote)
                .multilineTextAlignment(.center)

            Text("HealthKit background is in development.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Alerts Only") {
                viewModel.selectBackgroundMode(.alertsOnly)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button("Enable HealthKit") {
                viewModel.selectBackgroundMode(.healthKit)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    private var mainScreen: some View {
        VStack(spacing: 10) {
            timerActionButton
            settingsPanel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
            if viewModel.isRunning {
                let volume = minVolume + (crownDetent * volumeStep)
                viewModel.updateSessionVolume(Float(clamp(volume, minVolume, maxVolume)))
            } else {
                let seconds = TimerViewModel.minTotalSeconds + Int(crownDetent) * TimerViewModel.totalStepSeconds
                viewModel.updateTotalDurationSeconds(clamp(seconds, TimerViewModel.minTotalSeconds, TimerViewModel.maxTotalSeconds))
            }
        } onIdle: {
            syncCrownValue()
        }
        .onAppear {
            syncCrownValue()
            crownFocused = true
            syncReducedProgress()
            viewModel.updateDisplayDimmed(isLuminanceReduced)
        }
        .onTapGesture { crownFocused = true }
        .onChange(of: viewModel.isRunning) { _, _ in
            syncCrownValue()
            crownFocused = true
            syncReducedProgress()
        }
        .onChange(of: viewModel.currentPhase) { _, _ in
            syncReducedProgress()
        }
        .onChange(of: isLuminanceReduced) { _, _ in
            viewModel.updateDisplayDimmed(isLuminanceReduced)
            syncReducedProgress()
        }
        .onChange(of: viewModel.totalDurationSeconds) { _, _ in
            if !viewModel.isRunning {
                syncCrownValue()
                syncReducedProgress()
            }
        }
        .onChange(of: viewModel.sessionVolume) { _, _ in
            if viewModel.isRunning {
                syncCrownValue()
            }
        }
    }

    @ViewBuilder
    private var timerActionButton: some View {
        let button = Button {
            if viewModel.isRunning {
                viewModel.stop()
            } else {
                viewModel.start()
            }
        } label: {
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.isRunning ? .red : .green)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((viewModel.isRunning ? Color.red : Color.green).opacity(0.14))
        )
        .overlay(
            Group {
                if viewModel.isRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.red, lineWidth: 6)
                        ProgressRoundedRect(progress: progressForDisplay, cornerRadius: 18)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            .animation(isLuminanceReduced ? nil : .linear(duration: 0.2), value: progressForDisplay)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.green, lineWidth: 6)
                }
            }
        )

        button
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

                if viewModel.showsHealthKitInDevelopmentNotice {
                    Text("HealthKit background is in development.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            crownDetent = clamp(steps, 0, maxVolumeSteps)
        } else {
            let steps = Double((viewModel.totalDurationSeconds - TimerViewModel.minTotalSeconds) / TimerViewModel.totalStepSeconds)
            crownDetent = clamp(steps, 0, maxDurationSteps)
        }
    }

    private func syncReducedProgress() {
        if !viewModel.isRunning {
            reducedProgress = 0
            return
        }
        reducedProgress = elapsedFraction
    }

    private var maxDurationSteps: Double {
        Double((TimerViewModel.maxTotalSeconds - TimerViewModel.minTotalSeconds) / TimerViewModel.totalStepSeconds)
    }

    private var maxVolumeSteps: Double {
        ((maxVolume - minVolume) / volumeStep).rounded()
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

    private var progressForDisplay: CGFloat {
        isLuminanceReduced ? reducedProgress : elapsedFraction
    }

    private func formatted(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
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
