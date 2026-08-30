import SwiftUI

struct ControlPanelView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case control = "Control"
        case fui = "FUI Showcase"
        var id: String { rawValue }
    }

    @State private var selectedPage: Page = .control
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @EnvironmentObject private var handTracking: HandTrackingModel
    @EnvironmentObject private var runtimeState: JarvisRuntimeState
    @EnvironmentObject private var debugState: JarvisDebugState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Page", selection: $selectedPage) {
                    ForEach(Page.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if selectedPage == .control {
                    controlPanelBody
                } else {
                    FUIShowcaseView()
                        .environmentObject(runtimeState)
                }
            }
        }
    }

    private var controlPanelBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("JARVIS VISION")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(handTracking.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                statusRow("Gesture", handTracking.frame.gesture.displayName, "hand.raised")
                statusRow("Hands", handTracking.frame.handCountDescription, "viewfinder")
                statusRow("Intensity", handTracking.frame.intensityDescription, "waveform.path.ecg")
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Picker("Renderer", selection: $runtimeState.selectedMode) {
                ForEach(JarvisImmersiveMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(runtimeState.isImmersiveOpen || runtimeState.isImmersiveTransitioning)

            if runtimeState.selectedMode == .metal {
                Toggle("Smoke Test", isOn: $runtimeState.metalSmokeTestEnabled)
                    .toggleStyle(.switch)
                    .disabled(runtimeState.isImmersiveOpen || runtimeState.isImmersiveTransitioning)
            }

            Toggle("Particle Emission", isOn: $runtimeState.particleEmissionEnabled)
                .toggleStyle(.switch)
            Toggle("Ring Interaction", isOn: $runtimeState.ringInteractionEnabled)
                .toggleStyle(.switch)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await toggleImmersiveSpace()
                    }
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(runtimeState.isImmersiveTransitioning)

                Button {
                    handTracking.resetGestureState()
                } label: {
                    Label("Reset", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(runtimeState.isImmersiveTransitioning)
            }

            if runtimeState.selectedMode == .metal {
                metalDebugPanel
            }

            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private var primaryActionTitle: String {
        if runtimeState.isImmersiveTransitioning {
            return runtimeState.isImmersiveOpen ? "Closing" : "Opening"
        }

        return runtimeState.isImmersiveOpen ? "Close" : "Open"
    }

    private var primaryActionIcon: String {
        if runtimeState.isImmersiveTransitioning {
            return "hourglass"
        }

        return runtimeState.isImmersiveOpen ? "xmark.circle" : "sparkles"
    }

    private func toggleImmersiveSpace() async {
        guard runtimeState.beginImmersiveTransition() else { return }

        if runtimeState.isImmersiveOpen {
            await dismissImmersiveSpace()
            handTracking.stop()
            runtimeState.finishImmersiveTransition(open: false)
        } else {
            if runtimeState.selectedMode == .metal {
                debugState.resetMetal()
                handTracking.start()
            }

            let watchdog = Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                guard runtimeState.isImmersiveTransitioning, !runtimeState.isImmersiveOpen else { return }
                runtimeState.finishImmersiveTransition(open: false)
                debugState.reportMetal(
                    status: "Open timeout",
                    detail: "openImmersiveSpace did not return in 8 seconds",
                    warning: true
                )
                handTracking.stop()
            }

            let result = await openImmersiveSpace(id: runtimeState.selectedMode.spaceID)
            watchdog.cancel()
            let opened = result == .opened
            if runtimeState.isImmersiveTransitioning {
                runtimeState.finishImmersiveTransition(open: opened)
            }

            if runtimeState.selectedMode == .metal {
                debugState.reportMetal(
                    status: opened ? "Space opened" : "Open failed",
                    detail: "openImmersiveSpace result: \(String(describing: result))",
                    warning: !opened
                )
            }

            if !opened {
                handTracking.stop()
            }
        }
    }

    private var metalDebugPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metal Debug")
                .font(.headline)

            statusRow("State", debugState.metalStatus, "cpu")
            statusRow("Frame", "\(debugState.metalFrameIndex)", "number")
            statusRow("Warnings", "\(debugState.metalWarningCount)", "exclamationmark.triangle")

            Text(debugState.metalDetail)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.cyan)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.system(size: 16, design: .rounded))
    }
}
