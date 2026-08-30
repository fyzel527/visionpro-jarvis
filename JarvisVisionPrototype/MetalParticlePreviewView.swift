import Metal
import MetalKit
import QuartzCore
import SwiftUI
import UIKit

struct MetalParticlePreviewView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.01, green: 0.014, blue: 0.024, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        if let device {
            let renderer = MetalParticleRenderer(device: device, colorPixelFormat: view.colorPixelFormat)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator {
        fileprivate var renderer: MetalParticleRenderer?
    }
}

fileprivate final class MetalParticleRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let particleBuffer: MTLBuffer
    private let emitterBuffer: MTLBuffer
    private let particleCount = 4_096
    private let emitterCount = 5
    private var lastTime = CACurrentMediaTime()
    private var startTime = CACurrentMediaTime()

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device

        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let computeFunction = library.makeFunction(name: "metalParticleUpdate"),
              let vertexFunction = library.makeFunction(name: "metalParticleVertex"),
              let fragmentFunction = library.makeFunction(name: "metalParticleFragment") else {
            return nil
        }

        do {
            computePipeline = try device.makeComputePipelineState(function: computeFunction)

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        self.commandQueue = commandQueue

        var particles = (0..<particleCount).map { index in
            MetalParticle(
                position: SIMD2<Float>(0, 0),
                velocity: SIMD2<Float>(0, 0),
                color: SIMD4<Float>(0.1, 0.85, 1.0, 1.0),
                life: 0,
                maxLife: 0,
                size: 1,
                seed: UInt32(index &* 747_796_405)
            )
        }

        guard let particleBuffer = device.makeBuffer(
            bytes: &particles,
            length: MemoryLayout<MetalParticle>.stride * particles.count,
            options: [.storageModeShared]
        ),
        let emitterBuffer = device.makeBuffer(
            length: MemoryLayout<MetalEmitter>.stride * emitterCount,
            options: [.storageModeShared]
        ) else {
            return nil
        }

        self.particleBuffer = particleBuffer
        self.emitterBuffer = emitterBuffer
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let now = CACurrentMediaTime()
        let deltaTime = min(Float(now - lastTime), 1.0 / 30.0)
        let time = Float(now - startTime)
        lastTime = now

        updateEmitters(time: time)

        var uniforms = MetalParticleUniforms(
            deltaTime: deltaTime,
            time: time,
            particleCount: UInt32(particleCount),
            emitterCount: UInt32(emitterCount),
            aspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
            padding0: 0,
            padding1: 0,
            padding2: 0
        )

        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(computePipeline)
            encoder.setBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setBuffer(emitterBuffer, offset: 0, index: 1)
            encoder.setBytes(&uniforms, length: MemoryLayout<MetalParticleUniforms>.stride, index: 2)

            let threadsPerGroup = MTLSize(width: computePipeline.threadExecutionWidth, height: 1, depth: 1)
            let groups = MTLSize(
                width: (particleCount + threadsPerGroup.width - 1) / threadsPerGroup.width,
                height: 1,
                depth: 1
            )
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalParticleUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateEmitters(time: Float) {
        let pointer = emitterBuffer.contents().bindMemory(to: MetalEmitter.self, capacity: emitterCount)
        let colors: [SIMD4<Float>] = [
            SIMD4<Float>(0.08, 0.95, 1.0, 1.0),
            SIMD4<Float>(0.2, 0.78, 1.0, 1.0),
            SIMD4<Float>(0.32, 0.58, 1.0, 1.0),
            SIMD4<Float>(0.52, 0.48, 1.0, 1.0),
            SIMD4<Float>(0.76, 0.40, 1.0, 1.0)
        ]

        for index in 0..<emitterCount {
            let offset = Float(index) - 2.0
            let x = offset * 0.17 + sin(time * 0.9 + Float(index)) * 0.025
            let y = -0.48 + cos(time * 1.1 + Float(index) * 0.72) * 0.035
            let direction = simd_normalize(SIMD2<Float>(offset * 0.08, 1.0))

            pointer[index] = MetalEmitter(
                position: SIMD2<Float>(x, y),
                direction: direction,
                color: colors[index]
            )
        }
    }
}

private struct MetalParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var life: Float
    var maxLife: Float
    var size: Float
    var seed: UInt32
}

private struct MetalEmitter {
    var position: SIMD2<Float>
    var direction: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct MetalParticleUniforms {
    var deltaTime: Float
    var time: Float
    var particleCount: UInt32
    var emitterCount: UInt32
    var aspect: Float
    var padding0: Float
    var padding1: Float
    var padding2: Float
}
