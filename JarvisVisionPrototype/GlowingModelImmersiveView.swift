import RealityKit
import SwiftUI

struct GlowingModelImmersiveView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            RealityView { content in
            let root = Entity()
            root.position = [0, 1.35, -1.2]
            root.scale = SIMD3<Float>(repeating: 1.25)

            var glow = UnlitMaterial(applyPostProcessToneMap: false)
            glow.color = .init(tint: UIColor(red: 0.05, green: 0.72, blue: 1.0, alpha: 0.18))
            glow.blending = .transparent(opacity: .init(scale: 0.22))
            glow.triangleFillMode = .lines
            glow.faceCulling = .none
            let inner = ModelEntity(mesh: .generateSphere(radius: 0.27), materials: [glow])
            let holographic = HolographicMaterialController()
            holographic.apply(to: inner)
            root.addChild(inner)

            var shellMaterial = UnlitMaterial(applyPostProcessToneMap: false)
            shellMaterial.color = .init(tint: UIColor(red: 0.12, green: 0.85, blue: 1.0, alpha: 0.14))
            shellMaterial.blending = .transparent(opacity: .init(scale: 0.16))
            shellMaterial.triangleFillMode = .lines
            shellMaterial.faceCulling = .none
            let shell = ModelEntity(mesh: .generateSphere(radius: 0.36), materials: [shellMaterial])
            root.addChild(shell)

            var haloMaterial = UnlitMaterial(applyPostProcessToneMap: false)
            haloMaterial.color = .init(tint: UIColor(red: 0.1, green: 0.45, blue: 1.0, alpha: 0.08))
            haloMaterial.blending = .transparent(opacity: .init(scale: 0.10))
            haloMaterial.triangleFillMode = .lines
            haloMaterial.faceCulling = .none
            let halo = ModelEntity(mesh: .generateSphere(radius: 0.47), materials: [haloMaterial])
            root.addChild(halo)

            // Thin additive-looking scan rings establish a spatial light field.
            let ringSpecs: [(Float, Float, SIMD3<Float>)] = [
                (0.40, 0.0, SIMD3<Float>(0, 0, 0)),
                (0.34, 0.12, SIMD3<Float>(0.35, 0.0, 0.0)),
                (0.30, -0.14, SIMD3<Float>(-0.25, 0.2, 0.0))
            ]
            for (radius, y, tilt) in ringSpecs {
                var ringMaterial = UnlitMaterial(applyPostProcessToneMap: false)
                ringMaterial.color = .init(tint: UIColor(red: 0.18, green: 0.9, blue: 1.0, alpha: 0.5))
                ringMaterial.blending = .transparent(opacity: .init(scale: 0.48))
                ringMaterial.triangleFillMode = .lines
                ringMaterial.faceCulling = .none
                let ring = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: radius), materials: [ringMaterial])
                ring.position.y = y
                ring.orientation = simd_quatf(angle: tilt.x, axis: [1, 0, 0])
                root.addChild(ring)
            }

            let particles = Entity()
            particles.components.set(HolographicParticles.makeEmitter())
            root.addChild(particles)

            let pulse = Float((sin(timeline.date.timeIntervalSinceReferenceDate * 2.4) + 1) * 0.5)
            let pulseScale = 1.0 + pulse * 0.08
            inner.scale = SIMD3<Float>(repeating: pulseScale)
            shell.scale = SIMD3<Float>(repeating: 0.98 + pulse * 0.06)
            halo.scale = SIMD3<Float>(repeating: 0.96 + pulse * 0.14)
            content.add(root)
            }
        }
        .background(Color.clear)
    }
}
