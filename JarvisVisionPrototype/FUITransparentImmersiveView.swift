import SwiftUI
import RealityKit

struct FUITransparentImmersiveView: View {
    var body: some View {
        RealityView { content, attachments in
            if let hud = attachments.entity(for: "clear-fui-hud") {
                hud.position = SIMD3<Float>(0, 1.35, -1.15)
                content.add(hud)
            }
        } attachments: {
            Attachment(id: "clear-fui-hud") {
                FUITransparentPanel()
                    .frame(width: 980, height: 720)
            }
        }
    }
}

private struct FUITransparentPanel: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var phase = false
    private let cyan = Color(red: 0.09, green: 0.79, blue: 0.90)

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("J.A.R.V.I.S.")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(cyan)
                        Text("CLEAR HUD // NO MATERIAL SURFACE")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                    Button { Task { await dismissImmersiveSpace() } } label: {
                        Image(systemName: "xmark").foregroundStyle(cyan).frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(cyan, lineWidth: 1))
                }

                HStack(spacing: 50) {
                    ZStack {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .stroke(cyan.opacity(0.75 - Double(index) * 0.12), lineWidth: 1.5)
                                .frame(width: CGFloat(100 + index * 42), height: CGFloat(100 + index * 42))
                                .scaleEffect(phase ? 1.08 : 0.94)
                                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(index) * 0.12), value: phase)
                        }
                        Image(systemName: "bolt.fill").font(.system(size: 34)).foregroundStyle(cyan)
                    }
                    .frame(width: 340, height: 340)

                    VStack(alignment: .leading, spacing: 18) {
                        clearMetric("SYSTEM", "ONLINE")
                        clearMetric("SIGNAL", "100%")
                        clearMetric("SURFACE", "CLEAR")
                    }
                }

                HStack(spacing: 28) {
                    clearRail("TACTICAL LINK")
                    clearRail("SENSOR ARRAY")
                    clearRail("READY")
                }
            }
            .frame(maxWidth: 1100)
            .padding(56)
        }
        .background(Color.clear)
        .task { phase = true }
    }

    private func clearMetric(_ title: String, _ value: String) -> some View {
        HStack(spacing: 18) {
            Text(title).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.65))
            Rectangle().fill(cyan.opacity(0.7)).frame(width: 46, height: 1)
            Text(value).font(.caption.monospaced().weight(.bold)).foregroundStyle(cyan)
        }
    }

    private func clearRail(_ title: String) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { _ in
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(cyan)
            }
            Text(title).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.72))
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(cyan.opacity(0.55)), alignment: .bottom)
    }
}
