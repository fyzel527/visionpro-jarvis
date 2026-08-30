import RealityKit
import SwiftUI

struct JarvisImmersiveView: View {
    @EnvironmentObject private var handTracking: HandTrackingModel
    @EnvironmentObject private var runtimeState: JarvisRuntimeState
    @State private var sceneController = JarvisSceneController()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation) { timeline in
                RealityView { content in
                    content.add(sceneController.root)
                } update: { _ in
                    sceneController.update(
                        frame: handTracking.frame,
                        time: timeline.date.timeIntervalSinceReferenceDate,
                        particleEmissionEnabled: runtimeState.particleEmissionEnabled,
                        ringInteractionEnabled: runtimeState.ringInteractionEnabled
                    )
                }
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 4) {
                Text("AR_SYSTEM_ACTIVE")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.cyan.opacity(0.8))
                Text(handTracking.frame.gesture.displayName.uppercased())
                    .font(.headline.monospaced())
                Text("HANDS \(handTracking.frame.handCountDescription)  •  \(handTracking.status)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(28)
        }
        .task {
            handTracking.start()
        }
        .onDisappear {
            handTracking.stop()
            runtimeState.immersiveSpaceDidDisappear()
        }
    }
}
