import CompositorServices
import SwiftUI

private let jarvisSpatialConfiguration = SRConfiguration(immersionStyle: .full)

struct JarvisMetalImmersiveContent: CompositorContent {
    let trackingState: JarvisTrackingStateStore
    let debugState: JarvisDebugState
    let smokeTestEnabled: Bool
    let particleEmissionEnabled: Bool
    let ringInteractionEnabled: Bool
    let glowingModelEnabled: Bool

    var body: some CompositorContent {
        CompositorLayer(configuration: JarvisMetalLayerConfiguration()) { layerRenderer in
            debugState.reportMetal(
                status: "Reference renderer starting",
                detail: "layered Metal + ARKit world tracking"
            )
            SpatialRenderer_InitAndRun(layerRenderer, jarvisSpatialConfiguration)
        }
    }
}

private struct JarvisMetalLayerConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(
        capabilities: LayerRenderer.Capabilities,
        configuration: inout LayerRenderer.Configuration
    ) {
        let supportsFoveation = capabilities.supportsFoveation
        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions =
            supportsFoveation ? [.foveationEnabled] : []
        let supportedLayouts = capabilities.supportedLayouts(options: options)

        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated
        configuration.isFoveationEnabled = supportsFoveation
        configuration.colorFormat = .rgba16Float
    }
}
