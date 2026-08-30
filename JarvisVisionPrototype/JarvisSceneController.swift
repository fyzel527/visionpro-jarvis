import ARKit
import RealityKit
import UIKit
import simd

@MainActor
final class JarvisSceneController {
    let root = Entity()

    private let particleMeshRoot = Entity()
    private let fingertipRoot = Entity()
    private let coreRoot = Entity()
    private var energyCore: ModelEntity?
    private var gestureReticle: ModelEntity?
    private var meshParticles: [MeshParticle] = []
    private var fingertipEmitters: [FingerEmitterKey: Entity] = [:]
    private var fingertipCores: [FingerEmitterKey: ModelEntity] = [:]
    private var lastPinchPoint: SIMD3<Float>?
    private var grabStartPoint: SIMD3<Float>?
    private var grabStartObjectPosition: SIMD3<Float>?
    private var interactionRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    init() {
        buildScene()
    }

    func update(
        frame: HandFrame,
        time: TimeInterval,
        particleEmissionEnabled: Bool,
        ringInteractionEnabled: Bool
    ) {
        let pulse = Float((sin(time * 7.0) + 1) * 0.5)
        updateParticleMesh(
            frame: frame,
            time: time,
            pulse: pulse,
            ringInteractionEnabled: ringInteractionEnabled
        )
        updateFingertips(frame: frame, pulse: pulse, particleEmissionEnabled: particleEmissionEnabled)
    }

    private func buildScene() {
        root.addChild(particleMeshRoot)
        root.addChild(coreRoot)
        root.addChild(fingertipRoot)

        buildParticleMesh()
        buildHudCore()
        let coreMesh = MeshResource.generateSphere(radius: 0.009)
        for chirality in FingerEmitterKey.trackedHands {
            for joint in FingerEmitterKey.trackedJoints {
                let key = FingerEmitterKey(chirality: chirality, joint: joint)
                let color = color(for: key)

                let core = ModelEntity(
                    mesh: coreMesh,
                    materials: [emissive(color, intensity: 4.0)]
                )
                core.scale = SIMD3<Float>(repeating: 0.001)
                fingertipRoot.addChild(core)
                fingertipCores[key] = core

                let emitterEntity = Entity()
                emitterEntity.components.set(makeFingertipEmitter(color: color, birthRate: 0))
                fingertipRoot.addChild(emitterEntity)
                fingertipEmitters[key] = emitterEntity
            }
        }
    }

    private func buildHudCore() {
        let coreMesh = MeshResource.generateSphere(radius: 0.11)
        let core = ModelEntity(
            mesh: coreMesh,
            materials: [emissive(UIColor(red: 0.02, green: 0.72, blue: 1.0, alpha: 1), intensity: 5.0)]
        )
        core.position = particleMeshRoot.position
        coreRoot.addChild(core)
        energyCore = core

        let reticleMesh = MeshResource.generateSphere(radius: 0.018)
        let reticle = ModelEntity(
            mesh: reticleMesh,
            materials: [emissive(.white, intensity: 3.0)]
        )
        reticle.scale = SIMD3<Float>(repeating: 0.001)
        coreRoot.addChild(reticle)
        gestureReticle = reticle
    }

    private func buildParticleMesh() {
        particleMeshRoot.position = SIMD3<Float>(0, 1.28, -1.08)

        let mesh = MeshResource.generateSphere(radius: 0.004)
        let materials = [
            emissive(UIColor(red: 0.08, green: 0.88, blue: 1.0, alpha: 1), intensity: 2.8),
            emissive(UIColor(red: 0.18, green: 0.64, blue: 1.0, alpha: 1), intensity: 2.5),
            emissive(UIColor(red: 0.38, green: 0.47, blue: 1.0, alpha: 1), intensity: 2.4),
            emissive(UIColor(red: 0.72, green: 0.42, blue: 1.0, alpha: 1), intensity: 2.3)
        ]

        let majorSegments = 44
        let minorSegments = 14
        let majorRadius: Float = 0.22
        let minorRadius: Float = 0.085

        for major in 0..<majorSegments {
            let u = Float(major) / Float(majorSegments) * .pi * 2
            for minor in 0..<minorSegments {
                let v = Float(minor) / Float(minorSegments) * .pi * 2
                let ringRadius = majorRadius + minorRadius * cos(v)
                let base = SIMD3<Float>(
                    ringRadius * cos(u),
                    minorRadius * sin(v),
                    ringRadius * sin(u)
                )
                let normal = SIMD3<Float>(cos(v) * cos(u), sin(v), cos(v) * sin(u)).safeNormalized
                let phase = Float(major) * 0.37 + Float(minor) * 0.91
                let material = materials[(major + minor) % materials.count]
                let point = ModelEntity(mesh: mesh, materials: [material])
                point.position = base
                point.scale = SIMD3<Float>(repeating: 0.8)
                particleMeshRoot.addChild(point)
                meshParticles.append(MeshParticle(entity: point, base: base, normal: normal, phase: phase))
            }
        }
    }

    private func updateParticleMesh(
        frame: HandFrame,
        time: TimeInterval,
        pulse: Float,
        ringInteractionEnabled: Bool
    ) {
        let gestureScale: Float
        if ringInteractionEnabled {
            // Combine the continuous hand signals so the ring responds even when
            // only one hand is visible. Pinch contracts; open palms expand.
            let expansion = max(frame.expansion, frame.openness * 0.28)
            let pinchContraction: Float = frame.gesture == .pinch ? 0.28 : 0
            gestureScale = max(0.58, 1 + expansion * 0.72 - pinchContraction)
        } else {
            gestureScale = 1
        }
        let breathingScale = gestureScale + pulse * 0.035
        particleMeshRoot.scale = .lerp(
            particleMeshRoot.scale,
            SIMD3<Float>(repeating: breathingScale),
            t: 0.08
        )

        // Pinch acts as a grab cursor, matching the browser HUD interaction.
        if frame.gesture == .pinch, let pinchPoint = frame.pinchPoint {
            if grabStartPoint == nil {
                grabStartPoint = pinchPoint
                grabStartObjectPosition = particleMeshRoot.position
            }
            if let grabStartPoint, let grabStartObjectPosition {
                let delta = (pinchPoint - grabStartPoint) * SIMD3<Float>(repeating: 0.8)
                let target = grabStartObjectPosition + delta
                particleMeshRoot.position = .lerp(particleMeshRoot.position, target, t: 0.18)
                energyCore?.position = particleMeshRoot.position
            }
            gestureReticle?.position = pinchPoint
            gestureReticle?.scale = SIMD3<Float>(repeating: 1.0 + pulse * 0.35)
        } else {
            grabStartPoint = nil
            grabStartObjectPosition = nil
            gestureReticle?.scale = SIMD3<Float>(repeating: 0.001)
        }

        let yaw = simd_quatf(angle: Float(time) * 0.18, axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: sin(Float(time) * 0.35) * 0.18, axis: SIMD3<Float>(1, 0, 0))
        if ringInteractionEnabled,
           frame.gesture == .pinch,
           let pinchPoint = frame.pinchPoint {
            if let lastPinchPoint {
                let delta = pinchPoint - lastPinchPoint
                let yawDelta = -delta.x * 4.8
                let pitchDelta = delta.y * 4.8
                interactionRotation = simd_quatf(angle: yawDelta, axis: SIMD3<Float>(0, 1, 0))
                    * simd_quatf(angle: pitchDelta, axis: SIMD3<Float>(1, 0, 0))
                    * interactionRotation
            }
            self.lastPinchPoint = pinchPoint
        } else {
            lastPinchPoint = nil
        }
        particleMeshRoot.orientation = interactionRotation * yaw * pitch

        for particle in meshParticles {
            let ripple = sin(Float(time) * 2.4 + particle.phase) * 0.018
            let shear = SIMD3<Float>(
                sin(Float(time) * 1.4 + particle.phase * 0.7) * 0.006,
                cos(Float(time) * 1.8 + particle.phase) * 0.007,
                sin(Float(time) * 1.2 + particle.phase * 1.3) * 0.006
            )
            let target = particle.base + particle.normal * ripple + shear
            particle.entity.position = .lerp(particle.entity.position, target, t: 0.18)

            let flicker = 0.72 + pulse * 0.24 + sin(Float(time) * 4.1 + particle.phase) * 0.12
            particle.entity.scale = SIMD3<Float>(repeating: flicker)
        }
    }

    private func updateFingertips(frame: HandFrame, pulse: Float, particleEmissionEnabled: Bool) {
        guard particleEmissionEnabled else {
            for key in fingertipEmitters.keys {
                setEmitter(key, birthRate: 0)
                fingertipCores[key]?.scale = SIMD3<Float>(repeating: 0.001)
            }
            return
        }
        let activeKeys = Set(frame.trackedHands.flatMap { trackedKeys(for: $0) })

        updateHand(frame.leftHand, pulse: pulse)
        updateHand(frame.rightHand, pulse: pulse)

        for key in fingertipEmitters.keys where !activeKeys.contains(key) {
            setEmitter(key, birthRate: 0)
            fingertipCores[key]?.scale = SIMD3<Float>(repeating: 0.001)
        }
    }

    private func updateHand(_ hand: TrackedHand?, pulse: Float) {
        guard let hand else { return }

        for joint in FingerEmitterKey.trackedJoints {
            let key = FingerEmitterKey(chirality: hand.chirality, joint: joint)
            guard let position = hand.joints[joint] else {
                setEmitter(key, birthRate: 0)
                fingertipCores[key]?.scale = SIMD3<Float>(repeating: 0.001)
                continue
            }

            if let emitter = fingertipEmitters[key] {
                emitter.position = .lerp(emitter.position, position, t: 0.42)
            }

            if let core = fingertipCores[key] {
                core.position = .lerp(core.position, position, t: 0.42)
                let scale = 0.85 + pulse * 0.45
                core.scale = SIMD3<Float>(repeating: scale)
            }

            setEmitter(key, birthRate: 190)
        }
    }

    private func trackedKeys(for hand: TrackedHand) -> [FingerEmitterKey] {
        FingerEmitterKey.trackedJoints.compactMap { joint in
            hand.joints[joint] == nil ? nil : FingerEmitterKey(chirality: hand.chirality, joint: joint)
        }
    }

    private func setEmitter(_ key: FingerEmitterKey, birthRate: Float) {
        guard let entity = fingertipEmitters[key],
              var emitter = entity.components[ParticleEmitterComponent.self] else {
            return
        }

        emitter.mainEmitter.birthRate = birthRate
        emitterEntitySet(entity, emitter)
    }

    private func emitterEntitySet(_ entity: Entity, _ emitter: ParticleEmitterComponent) {
        entity.components.set(emitter)
    }

    private func makeFingertipEmitter(color: UIColor, birthRate: Float) -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent.Presets.magic
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = SIMD3<Float>(0.022, 0.022, 0.022)
        emitter.speed = 0.035
        emitter.speedVariation = 0.07
        emitter.radialAmount = 0.85
        emitter.mainEmitter.birthRate = birthRate
        emitter.mainEmitter.lifeSpan = 0.85
        emitter.mainEmitter.size = 0.007
        emitter.mainEmitter.sizeVariation = 0.006
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.vortexStrength = 0.24
        emitter.mainEmitter.color = .evolving(
            start: .single(color.withAlphaComponent(1.0)),
            end: .single(color.withAlphaComponent(0.0))
        )
        return emitter
    }

    private func color(for key: FingerEmitterKey) -> UIColor {
        let rightHandBoost: CGFloat = key.chirality == .right ? 0.18 : 0

        switch key.joint {
        case .thumbTip:
            return UIColor(red: 0.1, green: 0.95, blue: 1.0, alpha: 1)
        case .indexFingerTip:
            return UIColor(red: 0.25 + rightHandBoost, green: 0.85, blue: 1.0, alpha: 1)
        case .middleFingerTip:
            return UIColor(red: 0.18, green: 0.62 + rightHandBoost, blue: 1.0, alpha: 1)
        case .ringFingerTip:
            return UIColor(red: 0.42, green: 0.45 + rightHandBoost, blue: 1.0, alpha: 1)
        case .littleFingerTip:
            return UIColor(red: 0.68, green: 0.38 + rightHandBoost, blue: 1.0, alpha: 1)
        default:
            return UIColor(red: 0.16, green: 0.82, blue: 1.0, alpha: 1)
        }
    }

    private func emissive(_ color: UIColor, intensity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = intensity
        material.roughness = 0.25
        material.metallic = 0.1
        return material
    }
}

private struct MeshParticle {
    let entity: ModelEntity
    let base: SIMD3<Float>
    let normal: SIMD3<Float>
    let phase: Float
}

private struct FingerEmitterKey: Hashable {
    let chirality: HandAnchor.Chirality
    let joint: HandSkeleton.JointName

    static let trackedHands: [HandAnchor.Chirality] = [.left, .right]
    static let trackedJoints: [HandSkeleton.JointName] = [
        .thumbTip,
        .indexFingerTip,
        .middleFingerTip,
        .ringFingerTip,
        .littleFingerTip
    ]
}
