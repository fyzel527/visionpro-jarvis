import RealityKit
import UIKit
import simd

struct HolographicParameters: Codable, Sendable {
    var primaryColor = SIMD4<Float>(0.08, 0.82, 1.0, 0.88)
    var highlightColor = SIMD4<Float>(1.0, 0.52, 0.08, 0.95)
    var emissionIntensity: Float = 4.0
    var fresnelPower: Float = 3.0
    var fresnelIntensity: Float = 1.0
    var noiseStrength: Float = 0.12
    var noiseScale: Float = 8.0
    var noiseSpeed: Float = 0.8
    var dissolveThreshold: Float = 0.08
    var dissolveStrength: Float = 0.2
    var dispersionAmount: Float = 0.015
    var dispersionEnabled = true
    var flickerAmplitude: Float = 0.04
    var flickerFrequency: Float = 5.0
    var flickerEnabled = true
}

enum HolographicState: Sendable { case dormant, idle, active, scanning, warning }

struct HolographicComponent: Component {
    var parameters = HolographicParameters()
    var state: HolographicState = .idle
}

@MainActor
final class HolographicMaterialController {
    private(set) var parameters: HolographicParameters
    private weak var entity: ModelEntity?
    private var baseScale: SIMD3<Float> = .one

    init(parameters: HolographicParameters = HolographicParameters()) {
        self.parameters = parameters
    }

    func apply(to entity: ModelEntity) {
        self.entity = entity
        baseScale = entity.scale
        entity.components.set(HolographicComponent(parameters: parameters))
        updateMaterial()
    }

    func update(parameters: HolographicParameters) {
        self.parameters = parameters
        updateMaterial()
    }

    func setState(_ state: HolographicState) {
        guard let entity else { return }
        var component = entity.components[HolographicComponent.self] ?? HolographicComponent()
        component.state = state
        entity.components.set(component)
        switch state {
        case .dormant: parameters.emissionIntensity = 1.2
        case .idle: parameters.emissionIntensity = 4.0
        case .active: parameters.emissionIntensity = 6.0
        case .scanning: parameters.emissionIntensity = 8.0
        case .warning: parameters.emissionIntensity = 6.0
        }
        updateMaterial()
    }

    func update(time: TimeInterval) {
        guard let entity else { return }
        let flicker = parameters.flickerEnabled
            ? 1 + sin(Float(time) * parameters.flickerFrequency) * parameters.flickerAmplitude
            : 1
        entity.scale = baseScale * flicker
    }

    private func updateMaterial() {
        guard let entity else { return }
        let color = UIColor(
            red: CGFloat(parameters.primaryColor.x),
            green: CGFloat(parameters.primaryColor.y),
            blue: CGFloat(parameters.primaryColor.z),
            alpha: CGFloat(parameters.primaryColor.w)
        )
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: color)
        material.blending = .transparent(opacity: .init(scale: max(0.08, min(0.72, parameters.primaryColor.w))))
        material.triangleFillMode = .lines
        material.faceCulling = .none
        entity.model?.materials = [material]
    }
}

enum HolographicParticles {
    static func makeEmitter(color: UIColor = UIColor(red: 0.08, green: 0.82, blue: 1, alpha: 1)) -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent.Presets.magic
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [0.16, 0.16, 0.16]
        emitter.speed = 0.025
        emitter.speedVariation = 0.04
        emitter.mainEmitter.birthRate = 65
        emitter.mainEmitter.lifeSpan = 1.2
        emitter.mainEmitter.size = 0.004
        emitter.mainEmitter.sizeVariation = 0.003
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.color = .evolving(start: .single(color), end: .single(color.withAlphaComponent(0)))
        return emitter
    }
}
