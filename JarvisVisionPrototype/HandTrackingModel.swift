import ARKit
import Foundation
import simd

enum JarvisGesture: Equatable, Sendable {
    case idle
    case palmOpen
    case pinch
    case twoHandExpand

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .palmOpen:
            "Palm Open"
        case .pinch:
            "Pinch"
        case .twoHandExpand:
            "Expand"
        }
    }
}

struct TrackedHand: Identifiable, Sendable {
    let chirality: HandAnchor.Chirality
    let joints: [HandSkeleton.JointName: SIMD3<Float>]

    var id: String { chirality.description }

    var wrist: SIMD3<Float>? { joints[.wrist] }
    var thumbTip: SIMD3<Float>? { joints[.thumbTip] }
    var indexTip: SIMD3<Float>? { joints[.indexFingerTip] }
    var middleTip: SIMD3<Float>? { joints[.middleFingerTip] }
    var ringTip: SIMD3<Float>? { joints[.ringFingerTip] }
    var littleTip: SIMD3<Float>? { joints[.littleFingerTip] }

    var palmCenter: SIMD3<Float>? {
        guard let wrist, let indexTip, let middleTip, let ringTip else { return nil }
        return (wrist + indexTip + middleTip + ringTip) / 4
    }

    var pinchPoint: SIMD3<Float>? {
        guard let thumbTip, let indexTip else { return nil }
        return (thumbTip + indexTip) / 2
    }

    var pinchDistance: Float? {
        guard let thumbTip, let indexTip else { return nil }
        return simd_distance(thumbTip, indexTip)
    }

    var openness: Float {
        guard let wrist else { return 0 }
        let tips = [thumbTip, indexTip, middleTip, ringTip, littleTip].compactMap { $0 }
        guard !tips.isEmpty else { return 0 }
        let average = tips.reduce(Float.zero) { $0 + simd_distance($1, wrist) } / Float(tips.count)
        return clamped((average - 0.08) / 0.09, 0, 1)
    }
}

struct HandFrame: Sendable {
    var leftHand: TrackedHand?
    var rightHand: TrackedHand?
    var gesture: JarvisGesture = .idle
    var focusPoint: SIMD3<Float>?
    var pinchPoint: SIMD3<Float>?
    var openness: Float = 0
    var expansion: Float = 0
    var updatedAt = Date()

    var trackedHands: [TrackedHand] {
        [leftHand, rightHand].compactMap { $0 }
    }

    var handCountDescription: String {
        "\(trackedHands.count)"
    }

    var intensityDescription: String {
        "\(Int(max(openness, expansion) * 100))%"
    }
}

final class JarvisTrackingStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private var currentFrame = HandFrame()
    private var worldTrackingProvider: WorldTrackingProvider?

    func updateFrame(_ frame: HandFrame) {
        lock.lock()
        currentFrame = frame
        lock.unlock()
    }

    func frame() -> HandFrame {
        lock.lock()
        let frame = currentFrame
        lock.unlock()
        return frame
    }

    func setWorldTrackingProvider(_ provider: WorldTrackingProvider?) {
        lock.lock()
        worldTrackingProvider = provider
        lock.unlock()
    }

    func deviceAnchor(atTimestamp timestamp: TimeInterval) -> DeviceAnchor? {
        lock.lock()
        let provider = worldTrackingProvider
        lock.unlock()
        return provider?.queryDeviceAnchor(atTimestamp: timestamp)
    }

    func reset() {
        lock.lock()
        currentFrame = HandFrame()
        worldTrackingProvider = nil
        lock.unlock()
    }
}

@MainActor
final class HandTrackingModel: ObservableObject {
    nonisolated let sharedState = JarvisTrackingStateStore()

    @Published private(set) var frame = HandFrame()
    @Published private(set) var status = "Ready"
    @Published private(set) var isTracking = false

    private var trackingTask: Task<Void, Never>?
    private var activeSession: ARKitSession?
    private var currentRunID: UUID?
    private var leftHand: TrackedHand?
    private var rightHand: TrackedHand?
    private var filteredJoints: [HandAnchor.Chirality: [HandSkeleton.JointName: SIMD3<Float>]] = [:]
    private var lastFilterTimestamp: TimeInterval?
    private var pinchLatched = false
    private var expansionLatched = false

    func start() {
        guard trackingTask == nil else { return }

        let session = ARKitSession()
        let handProvider = HandTrackingProvider()
        let worldProvider = WorldTrackingProvider.isSupported ? WorldTrackingProvider() : nil
        let runID = UUID()

        activeSession = session
        currentRunID = runID
        isTracking = true
        status = "Starting hand tracking"

        trackingTask = Task { [weak self] in
            await self?.runSession(
                session: session,
                handProvider: handProvider,
                worldProvider: worldProvider,
                runID: runID
            )
        }
    }

    func stop() {
        let session = activeSession
        trackingTask?.cancel()
        trackingTask = nil
        activeSession = nil
        currentRunID = nil
        session?.stop()
        leftHand = nil
        rightHand = nil
        filteredJoints.removeAll()
        lastFilterTimestamp = nil
        pinchLatched = false
        expansionLatched = false
        frame = HandFrame()
        sharedState.reset()
        SpatialRenderer_SetHandTrackingState(0, 0, 0, 0, 0, 0, 0)
        isTracking = false
        status = "Stopped"
    }

    func resetGestureState() {
        leftHand = nil
        rightHand = nil
        frame = HandFrame()
        filteredJoints.removeAll()
        lastFilterTimestamp = nil
        pinchLatched = false
        expansionLatched = false
        sharedState.updateFrame(frame)
        SpatialRenderer_SetHandTrackingState(0, 0, 0, 0, 0, 0, 0)
    }

    private func runSession(
        session: ARKitSession,
        handProvider: HandTrackingProvider,
        worldProvider: WorldTrackingProvider?,
        runID: UUID
    ) async {
        defer {
            finishRun(runID: runID)
        }

        guard isCurrentRun(runID) else { return }

        guard HandTrackingProvider.isSupported else {
            status = "Hand tracking is not supported"
            return
        }

        let authorization = await session.requestAuthorization(for: [.handTracking])
        guard isCurrentRun(runID) else {
            session.stop()
            return
        }

        guard authorization[.handTracking] == .allowed else {
            status = "Hand tracking permission denied"
            return
        }

        do {
            var providers: [any DataProvider] = [handProvider]
            if let worldProvider {
                providers.append(worldProvider)
            }

            try await session.run(providers)
            guard isCurrentRun(runID) else {
                session.stop()
                return
            }

            sharedState.setWorldTrackingProvider(worldProvider)
            status = "Hand tracking running"
            await consumeSessionEvents(session: session, handProvider: handProvider, runID: runID)
        } catch is CancellationError {
            session.stop()
        } catch {
            if isCurrentRun(runID) {
                status = "ARKit error: \(error.localizedDescription)"
            }
        }
    }

    private func finishRun(runID: UUID) {
        guard isCurrentRun(runID) else { return }

        trackingTask = nil
        activeSession = nil
        currentRunID = nil
        leftHand = nil
        rightHand = nil
        filteredJoints.removeAll()
        lastFilterTimestamp = nil
        pinchLatched = false
        expansionLatched = false
        frame = HandFrame()
        sharedState.reset()
        isTracking = false

        if status == "Starting hand tracking" || status == "Hand tracking running" {
            status = "Stopped"
        }
    }

    private func isCurrentRun(_ runID: UUID) -> Bool {
        currentRunID == runID
    }

    private func consumeSessionEvents(session: ARKitSession, handProvider: HandTrackingProvider, runID: UUID) async {
        let eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in session.events {
                if Task.isCancelled { return }
                self.handleSessionEvent(event, runID: runID)
            }
        }
        defer {
            eventTask.cancel()
        }

        for await update in handProvider.anchorUpdates {
            if Task.isCancelled || !isCurrentRun(runID) {
                return
            }
            handleHandUpdate(update, runID: runID)
        }
    }

    private func handleSessionEvent(_ event: ARKitSession.Event, runID: UUID) {
        guard isCurrentRun(runID) else { return }

        switch event {
        case .authorizationChanged(let type, let status):
            self.status = "\(type.description): \(status.description)"
        case .dataProviderStateChanged(_, let newState, let error):
            if let error {
                self.status = "Provider \(newState.description): \(error.localizedDescription)"
            } else {
                self.status = "Provider \(newState.description)"
            }
        @unknown default:
            self.status = "ARKit session event"
        }
    }

    private func handleHandUpdate(_ update: AnchorUpdate<HandAnchor>, runID: UUID) {
        guard isCurrentRun(runID) else { return }

        let anchor = update.anchor

        if update.event == .removed || !anchor.isTracked {
            if anchor.chirality == .left {
                leftHand = nil
            } else {
                rightHand = nil
            }
            filteredJoints[anchor.chirality] = nil
            publishFrame()
            return
        }

        guard let hand = trackedHand(from: anchor) else { return }
        if hand.chirality == .left {
            leftHand = hand
        } else {
            rightHand = hand
        }
        publishFrame()
    }

    private func trackedHand(from anchor: HandAnchor) -> TrackedHand? {
        guard let skeleton = anchor.handSkeleton else { return nil }

        var joints: [HandSkeleton.JointName: SIMD3<Float>] = [:]
        for name in HandSkeleton.JointName.allCases {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { continue }
            let worldFromJoint = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            joints[name] = worldFromJoint.translation
        }

        guard !joints.isEmpty else { return nil }

        // Smooth the official ARKit joint stream before it reaches gesture
        // classification or either renderer. The adaptive exponential filter
        // is responsive during motion and settles quickly when the hand stops.
        let now = Date().timeIntervalSinceReferenceDate
        let dt = min(max(now - (lastFilterTimestamp ?? now), 1.0 / 120.0), 0.1)
        lastFilterTimestamp = now
        let tau = 0.045
        let alpha = Float(1.0 - exp(-dt / tau))
        var previous = filteredJoints[anchor.chirality] ?? [:]
        for (name, value) in joints {
            if let old = previous[name] {
                previous[name] = old + (value - old) * alpha
            } else {
                previous[name] = value
            }
        }
        filteredJoints[anchor.chirality] = previous
        return TrackedHand(chirality: anchor.chirality, joints: previous)
    }

    private func publishFrame() {
        var next = HandFrame(leftHand: leftHand, rightHand: rightHand)
        next.openness = max(leftHand?.openness ?? 0, rightHand?.openness ?? 0)

        let pinchCandidates = next.trackedHands.compactMap { hand -> (Float, SIMD3<Float>)? in
            guard let distance = hand.pinchDistance, let point = hand.pinchPoint else { return nil }
            return (distance, point)
        }
        let bestPinch = pinchCandidates.min { $0.0 < $1.0 }

        if let bestPinch {
            if pinchLatched {
                pinchLatched = bestPinch.0 < 0.045
            } else {
                pinchLatched = bestPinch.0 < 0.030
            }
        } else {
            pinchLatched = false
        }

        if pinchLatched, let bestPinch {
            next.gesture = .pinch
            next.pinchPoint = bestPinch.1
            next.focusPoint = bestPinch.1
        } else if let left = leftHand?.palmCenter, let right = rightHand?.palmCenter {
            let distance = simd_distance(left, right)
            next.expansion = clamped((distance - 0.22) / 0.50, 0, 1)
            next.focusPoint = (left + right) / 2
            if expansionLatched {
                expansionLatched = next.expansion > 0.34
            } else {
                expansionLatched = next.expansion > 0.42
            }
            next.gesture = expansionLatched ? .twoHandExpand : .idle
        } else if next.openness > 0.50 {
            next.gesture = .palmOpen
            next.focusPoint = leftHand?.palmCenter ?? rightHand?.palmCenter
        } else {
            next.gesture = .idle
            next.focusPoint = leftHand?.palmCenter ?? rightHand?.palmCenter
        }

        next.updatedAt = Date()
        frame = next
        sharedState.updateFrame(next)

        let metalGesture: Int32
        switch next.gesture {
        case .idle: metalGesture = 0
        case .palmOpen: metalGesture = 1
        case .pinch: metalGesture = 2
        case .twoHandExpand: metalGesture = 3
        }
        let pinch = next.pinchPoint ?? .zero
        SpatialRenderer_SetHandTrackingState(
            metalGesture,
            pinch.x,
            pinch.y,
            pinch.z,
            next.pinchPoint == nil ? 0 : 1,
            next.openness,
            next.expansion
        )
    }
}
