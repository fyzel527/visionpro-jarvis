import SwiftUI

enum JarvisSpace {
    static let realityID = "JarvisImmersiveSpace"
    static let metalID = "JarvisMetalImmersiveSpace"
    static let fuiID = "JarvisFUIImmersiveSpace"
    static let clearFUIID = "JarvisClearFUIImmersiveSpace"
    static let glowingModelID = "JarvisGlowingModelImmersiveSpace"
}

enum JarvisImmersiveMode: String, CaseIterable, Identifiable {
    case metal
    case realityKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metal:
            "Metal"
        case .realityKit:
            "RealityKit"
        }
    }

    var spaceID: String {
        switch self {
        case .metal:
            JarvisSpace.metalID
        case .realityKit:
            JarvisSpace.realityID
        }
    }
}

@main
struct JarvisVisionPrototypeApp: App {
    @StateObject private var handTracking = HandTrackingModel()
    @StateObject private var runtimeState = JarvisRuntimeState()
    @StateObject private var debugState = JarvisDebugState()
    @State private var realityImmersionStyle: ImmersionStyle = .mixed
    @State private var metalImmersionStyle: ImmersionStyle = .full
    @State private var glowingModelImmersionStyle: ImmersionStyle = .full

    var body: some Scene {
        WindowGroup {
            ControlPanelView()
                .environmentObject(handTracking)
                .environmentObject(runtimeState)
                .environmentObject(debugState)
        }
        .defaultSize(width: 460, height: 720)
        .windowStyle(.plain)

        ImmersiveSpace(id: JarvisSpace.realityID) {
            JarvisImmersiveView()
                .environmentObject(handTracking)
                .environmentObject(runtimeState)
        }
        .immersionStyle(selection: $realityImmersionStyle, in: .mixed)

        ImmersiveSpace(id: JarvisSpace.metalID) {
            JarvisMetalImmersiveContent(
                trackingState: handTracking.sharedState,
                debugState: debugState,
                smokeTestEnabled: runtimeState.metalSmokeTestEnabled,
                particleEmissionEnabled: runtimeState.particleEmissionEnabled,
                ringInteractionEnabled: runtimeState.ringInteractionEnabled,
                glowingModelEnabled: runtimeState.glowingModelEnabled
            )
        }
        .immersionStyle(selection: $metalImmersionStyle, in: .full)

        ImmersiveSpace(id: JarvisSpace.fuiID) {
            FUIImmersiveView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: JarvisSpace.clearFUIID) {
            FUITransparentImmersiveView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: JarvisSpace.glowingModelID) {
            JarvisMetalImmersiveContent(
                trackingState: handTracking.sharedState,
                debugState: debugState,
                smokeTestEnabled: false,
                particleEmissionEnabled: true,
                ringInteractionEnabled: false,
                glowingModelEnabled: true
            )
        }
        .immersionStyle(selection: $glowingModelImmersionStyle, in: .full)
    }
}
