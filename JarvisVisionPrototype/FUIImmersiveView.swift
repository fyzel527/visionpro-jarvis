import SwiftUI
import RealityKit

struct FUIImmersiveView: View {
    var body: some View {
        RealityView { content, attachments in
            if let hud = attachments.entity(for: "fui-hud") {
                hud.position = SIMD3<Float>(0, 1.35, -1.15)
                content.add(hud)
            }
        } attachments: {
            Attachment(id: "fui-hud") {
                FUIMaterialPanel().frame(width: 980, height: 720)
            }
        }
    }
}

private struct FUIMaterialPanel: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Mixed immersion leaves the real-world environment visible behind
            // the floating FUI surfaces.
            Color.clear.ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("J.A.R.V.I.S.")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(fuiImmersiveCyan)
                        Text("FULL IMMERSIVE HUD // MARK XI")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Button {
                        Task { await dismissImmersiveSpace() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(fuiImmersiveCyan.opacity(0.35)))

                HStack(spacing: 28) {
                    immersivePulse
                    VStack(alignment: .leading, spacing: 14) {
                        immersiveMetric("SYSTEM", "ONLINE")
                        immersiveMetric("LINK", "STABLE")
                        immersiveMetric("MODE", "FUI FULL")
                    }
                    .padding(20)
                    .frame(width: 250)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 18) {
                    immersiveRail(title: "TACTICAL LINK")
                    immersiveRail(title: "CALIBRATION")
                    immersiveRail(title: "SENSOR ARRAY")
                }
            }
            .frame(maxWidth: 980)
            .padding(50)
        }
        .task { pulse = true }
        .background(Color.clear)
    }

    private var immersivePulse: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let opacity = 0.5 - Double(index) * 0.06
                let diameter = CGFloat(100 + index * 38)
                Circle()
                    .stroke(fuiImmersiveCyan.opacity(opacity), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(Double(index) * 0.12), value: pulse)
            }
            Circle().fill(fuiImmersiveCyan.opacity(0.24)).frame(width: 86, height: 86)
            Image(systemName: "bolt.fill").font(.system(size: 30)).foregroundStyle(fuiImmersiveCyan)
        }
        .frame(width: 340, height: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(fuiImmersiveCyan.opacity(0.35)))
    }

    private func immersiveMetric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value).font(.caption.monospaced().weight(.bold)).foregroundStyle(fuiImmersiveCyan)
        }
    }

    private func immersiveRail(title: String) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { _ in
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(fuiImmersiveCyan)
            }
            Text(title).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.65))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fuiImmersiveCyan.opacity(0.3)))
    }
}

private let fuiImmersiveCyan = Color(red: 0.09, green: 0.79, blue: 0.90)
