import SwiftUI

private let fuiCyan = Color(red: 0.09, green: 0.79, blue: 0.90)

struct FUIShowcaseView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @EnvironmentObject private var runtimeState: JarvisRuntimeState
    @State private var fuiImmersiveOpen = false
    @State private var clearFUIOpen = false
    @State private var glowingModelOpen = false
    @State private var pulse = false
    @State private var circlesExpanded = false
    @State private var hexagonsExpanded = false
    @State private var chevronsLit = false
    @State private var trianglesActive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                HStack(spacing: 16) {
                    FUIStatusCard(title: "SYSTEM", value: "ONLINE", symbol: "bolt.fill")
                    FUIStatusCard(title: "MODE", value: "MARK XI", symbol: "scope")
                }

                HStack(spacing: 20) {
                    Button { withAnimation(.easeInOut(duration: 0.5)) { circlesExpanded.toggle() } } label: {
                        FUIExpandingCircles(expanded: circlesExpanded)
                    }
                    .buttonStyle(.plain)

                    Button { withAnimation(.easeInOut(duration: 0.5)) { hexagonsExpanded.toggle() } } label: {
                        FUIExpandingHexagons(expanded: hexagonsExpanded)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 20) {
                    Button { withAnimation(.easeInOut(duration: 0.8)) { pulse.toggle() } } label: {
                        FUIPulseRings(active: pulse)
                    }
                    .buttonStyle(.plain)

                FUIWarningBanner()

                Button {
                    Task {
                        if fuiImmersiveOpen {
                            await dismissImmersiveSpace()
                            fuiImmersiveOpen = false
                        } else {
                            if clearFUIOpen {
                                await dismissImmersiveSpace()
                                clearFUIOpen = false
                            }
                            let result = await openImmersiveSpace(id: JarvisSpace.fuiID)
                            fuiImmersiveOpen = result == .opened
                        }
                    }
                } label: {
                    Label(
                        fuiImmersiveOpen ? "EXIT FUI HUD" : "ENTER FUI HUD",
                        systemImage: fuiImmersiveOpen ? "rectangle.portrait.and.arrow.right" : "viewfinder.circle"
                    )
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(fuiCyan, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        if glowingModelOpen {
                            await dismissImmersiveSpace()
                            runtimeState.glowingModelEnabled = false
                            glowingModelOpen = false
                        } else {
                            if fuiImmersiveOpen || clearFUIOpen {
                                await dismissImmersiveSpace()
                                fuiImmersiveOpen = false
                                clearFUIOpen = false
                            }
                            runtimeState.metalSmokeTestEnabled = false
                            runtimeState.particleEmissionEnabled = true
                            runtimeState.glowingModelEnabled = true
                            let result = await openImmersiveSpace(id: JarvisSpace.metalID)
                            glowingModelOpen = result == .opened
                            if result != .opened {
                                runtimeState.glowingModelEnabled = false
                            }
                        }
                    }
                } label: {
                    Label(glowingModelOpen ? "EXIT GLOWING MODEL" : "SHOW GLOWING 3D MODEL", systemImage: "cube.transparent")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(fuiCyan)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(fuiCyan, lineWidth: 1.5))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        if clearFUIOpen {
                            await dismissImmersiveSpace()
                            clearFUIOpen = false
                        } else {
                            if fuiImmersiveOpen {
                                await dismissImmersiveSpace()
                                fuiImmersiveOpen = false
                            }
                            let result = await openImmersiveSpace(id: JarvisSpace.clearFUIID)
                            clearFUIOpen = result == .opened
                        }
                    }
                } label: {
                    Label(
                        clearFUIOpen ? "EXIT CLEAR FUI" : "ENTER CLEAR FUI",
                        systemImage: clearFUIOpen ? "xmark.circle" : "sparkles"
                    )
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(fuiCyan)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(fuiCyan, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

                Button { withAnimation(.easeInOut(duration: 0.7)) { chevronsLit.toggle() } } label: {
                    FUIChevronRail(active: chevronsLit)
                }
                .buttonStyle(.plain)

                Button { withAnimation(.easeInOut(duration: 1.2)) { trianglesActive.toggle() } } label: {
                    FUITrianglePulse(active: trianglesActive)
                }
                .buttonStyle(.plain)

                FUIVerticalChevronPanel(active: chevronsLit)

                FUIGlowingBox {
                    Text(futureScape("IMMERSIVE LINK ESTABLISHED"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(fuiCyan)
                }
            }
            .padding(28)
        }
        .background(Color.clear)
        .navigationTitle("FUI SHOWCASE")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("J.A.R.V.I.S.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(fuiCyan)
            Text("FICTIONAL USER INTERFACE // MARK XI")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.62))
            HStack(spacing: 12) {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                    Text(day.prefix(3).uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(day == Calendar.current.shortWeekdaySymbols[Calendar.current.component(.weekday, from: Date()) - 1] ? fuiCyan : .white.opacity(0.45))
                }
            }
        }
    }
}

private func futureScape(_ input: String) -> String {
    input.uppercased().replacingOccurrences(of: "E", with: "Ξ")
}

private struct FUIStatusCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(fuiCyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.5))
                Text(value).font(.caption.monospaced().weight(.bold)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(fuiCyan.opacity(0.35)))
    }
}

private struct FUIExpandingCircles: View {
    let expanded: Bool
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle().stroke(fuiCyan.opacity(0.28), lineWidth: 1)
                    .frame(width: 26, height: 26)
                    .offset(y: expanded ? CGFloat(index - 3) * 30 : 0)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
            Circle().fill(fuiCyan.opacity(0.2)).overlay(Circle().stroke(fuiCyan, lineWidth: 2)).frame(width: 30, height: 30)
        }
        .frame(width: 150, height: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FUIExpandingHexagons: View {
    let expanded: Bool
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                RegularPolygon(sides: 6).stroke(fuiCyan.opacity(0.35), lineWidth: 1)
                    .frame(width: 28, height: 28)
                    .offset(x: expanded ? cos(Double(index) * .pi / 3) * 42 : 0,
                            y: expanded ? sin(Double(index) * .pi / 3) * 42 : 0)
            }
            RegularPolygon(sides: 6).fill(fuiCyan.opacity(0.18)).overlay(RegularPolygon(sides: 6).stroke(fuiCyan, lineWidth: 2)).frame(width: 34, height: 34)
        }
        .frame(width: 150, height: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FUIPulseRings: View {
    let active: Bool
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Circle().stroke(fuiCyan.opacity(active ? 0.55 - Double(index) * 0.09 : 0.25), lineWidth: 2)
                    .frame(width: CGFloat(34 + index * 20), height: CGFloat(34 + index * 20))
                    .scaleEffect(active ? 1.15 : 1)
                    .animation(.easeInOut(duration: 1.2).delay(Double(index) * 0.08), value: active)
            }
            Circle().fill(fuiCyan.opacity(0.3)).frame(width: 28, height: 28)
        }
        .frame(width: 150, height: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FUIWarningBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("WARNING").font(.caption.monospaced().weight(.bold)).foregroundStyle(.orange)
                Text("CALIBRATION REQUIRED").font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.45)))
    }
}

private struct FUITrianglePulse: View {
    let active: Bool
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                RegularPolygon(sides: 3).stroke(fuiCyan.opacity(active ? 0.45 - Double(index) * 0.07 : 0.2), lineWidth: 2)
                    .frame(width: CGFloat(32 + index * 22), height: CGFloat(32 + index * 22))
                    .scaleEffect(active ? 1.2 : 1)
                    .animation(.easeInOut(duration: 1.2).delay(Double(index) * 0.12), value: active)
            }
            RegularPolygon(sides: 3).fill(fuiCyan.opacity(0.25)).frame(width: 30, height: 30)
        }
        .frame(width: 150, height: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FUIVerticalChevronPanel: View {
    let active: Bool
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { index in
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(active ? fuiCyan : .white.opacity(0.2))
                    .animation(.easeInOut(duration: 0.4).delay(Double(9 - index) * 0.08), value: active)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(fuiCyan.opacity(0.3)))
    }
}

private struct FUIGlowingBox<Content: View>: View {
    let content: Content
    @State private var glow = false
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fuiCyan.opacity(glow ? 0.35 : 0.9), lineWidth: 2).shadow(color: fuiCyan.opacity(glow ? 0.8 : 0.25), radius: 10))
            .onAppear { glow = true }
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: glow)
    }
}

private struct FUIChevronRail: View {
    let active: Bool
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                Image(systemName: "chevron.right")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(active ? fuiCyan : .white.opacity(0.25))
                    .animation(.easeInOut(duration: 0.4).delay(Double(index) * 0.08), value: active)
            }
            Spacer()
            Text("TACTICAL LINK").font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.55))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(fuiCyan.opacity(0.3)))
    }
}

private struct RegularPolygon: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<sides {
            let angle = Double(index) * 2 * .pi / Double(sides) - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
