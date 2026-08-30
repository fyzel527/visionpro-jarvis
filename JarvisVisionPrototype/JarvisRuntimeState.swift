import Foundation

@MainActor
final class JarvisRuntimeState: ObservableObject {
    @Published private(set) var isImmersiveOpen = false
    @Published private(set) var isImmersiveTransitioning = false
    @Published var selectedMode: JarvisImmersiveMode = .metal
    @Published var metalSmokeTestEnabled = true
    @Published var particleEmissionEnabled = true
    @Published var ringInteractionEnabled = true
    @Published var glowingModelEnabled = false

    func beginImmersiveTransition() -> Bool {
        guard !isImmersiveTransitioning else { return false }

        isImmersiveTransitioning = true
        return true
    }

    func finishImmersiveTransition(open: Bool) {
        isImmersiveOpen = open
        isImmersiveTransitioning = false
    }

    func immersiveSpaceDidDisappear() {
        isImmersiveOpen = false
    }
}

@MainActor
final class JarvisDebugState: ObservableObject, @unchecked Sendable {
    @Published private(set) var metalStatus = "Idle"
    @Published private(set) var metalDetail = "Metal renderer has not opened"
    @Published private(set) var metalFrameIndex: UInt64 = 0
    @Published private(set) var metalWarningCount: UInt64 = 0
    @Published private(set) var metalLastUpdated = Date()

    func resetMetal() {
        metalStatus = "Opening"
        metalDetail = "Waiting for CompositorLayer"
        metalFrameIndex = 0
        metalWarningCount = 0
        metalLastUpdated = Date()
    }

    nonisolated func reportMetal(
        status: String,
        detail: String? = nil,
        frameIndex: UInt64? = nil,
        warning: Bool = false
    ) {
        Task { @MainActor in
            self.metalStatus = status
            if let detail {
                self.metalDetail = detail
            }
            if let frameIndex {
                self.metalFrameIndex = frameIndex
            }
            if warning {
                self.metalWarningCount += 1
            }
            self.metalLastUpdated = Date()
        }
    }
}
