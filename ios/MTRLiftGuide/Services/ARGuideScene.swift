//
//  ARGuideScene.swift
//  MTR Lift Guide
//
//  Real augmented reality for the guidance screen. An ARKit world-tracking
//  session maps the station floor / walls, and a RealityKit marker is anchored
//  onto whichever surface is in front of the phone.
//
//  Two visual modes share the same anchoring:
//    • guide — a slim arrow with a flowing trail of dashes;
//    • game  — a line of coins to walk through, popped one by one.
//

import ARKit
import Combine
import RealityKit
import SwiftUI
import UIKit
import simd

/// Owns the `ARView`, its session and the anchored content.
final class ARGuideController: NSObject, ObservableObject {

    /// Which surface the marker landed on.
    enum Alignment: Equatable {
        case floor
        case wall
    }

    enum Status: Equatable {
        case idle
        case searching
        case placed(Alignment)
    }

    enum Failure: Equatable {
        case unsupported
        case cameraDenied
        case interrupted(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var failure: Failure?
    @Published private(set) var gameMode = false
    @Published private(set) var coinsCollected = 0
    @Published private(set) var coinsRemaining = 0

    let arView: ARView

    /// Everything that hangs off the current anchor.
    private struct Assembly {
        let anchor: AnchorEntity
        let root: Entity
        let body: Entity
        let flow: [Entity]
        let coins: [ModelEntity]
    }

    private var assembly: Assembly?
    private var planeNormal = SIMD3<Float>(0, 1, 0)

    private var targetBearing: Double = 0
    private var deviceHeading: Double = 0
    private var headingAvailable = false

    private var cameraYaw: Float = 0
    private var previousCameraYaw: Float?
    private var turnRate: Float = 0
    private var compassOffset: Float?
    private var frozenYaw: Float?

    // Movement, used to make sure a coin only counts when the user is actually
    // walking the way the arrow points.
    private var lastCameraPosition: SIMD3<Float>?
    private var cameraVelocity = SIMD3<Float>(0, 0, 0)
    private var travelUnit = SIMD3<Float>(0, 0, 1)

    private var elapsed: Float = 0
    private var assemblyAge: Float = 0
    private var lastAttempt: Float = -10
    private var searchStartedAt: Float = 0
    private var usingFallback = false
    private var coinPickups: [ObjectIdentifier: Float] = [:]

    private var running = false
    private var subscription: Cancellable?

    override init() {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView = view
        super.init()
        view.environment.sceneUnderstanding.options.insert(.occlusion)
        view.session.delegate = self
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(deltaTime: Float(event.deltaTime))
        }
    }

    // MARK: - Lifecycle

    /// World tracking with floors and walls enabled; scene depth (LiDAR) is
    /// added when the device supports it so the marker hides behind furniture.
    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        return configuration
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            failure = .unsupported
            return
        }

        clearAssembly()
        resetCompassCalibration()
        failure = nil
        running = true
        arView.session.run(makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        running = false
        arView.session.pause()
    }

    /// Drop the marker and map the surroundings again.
    func recenter() {
        guard running else {
            start()
            return
        }
        clearAssembly()
        resetCompassCalibration()
        failure = nil
        arView.session.run(makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    /// Resetting tracking throws away the world origin, so the old
    /// camera↔compass mapping no longer means anything.
    private func resetCompassCalibration() {
        compassOffset = nil
        frozenYaw = nil
        previousCameraYaw = nil
        turnRate = 0
        lastCameraPosition = nil
        cameraVelocity = SIMD3<Float>(0, 0, 0)
    }

    // MARK: - Guidance input

    func setTarget(bearing: Double) {
        targetBearing = bearing
    }

    func setHeading(_ heading: Double, available: Bool) {
        deviceHeading = heading
        headingAvailable = available
    }

    /// Swaps between the arrow and the coin trail. Re-anchoring keeps the new
    /// content where the user is actually looking.
    func setGameMode(_ enabled: Bool) {
        guard enabled != gameMode else { return }
        gameMode = enabled
        coinsCollected = 0
        coinsRemaining = 0
        if assembly != nil {
            clearAssembly()
        }
    }

    // MARK: - Frame loop

    private func tick(deltaTime: Float) {
        guard running else { return }
        elapsed += deltaTime
        assemblyAge += deltaTime

        if let frame = arView.session.currentFrame {
            let columns = frame.camera.transform.columns
            let forward = -columns.2
            let yaw = Float(atan2(Double(forward.x), Double(forward.z)))
            if let previous = previousCameraYaw {
                turnRate = abs(shortestAngle(yaw - previous)) / max(deltaTime, 0.001)
            }
            previousCameraYaw = yaw
            cameraYaw = yaw

            let position = SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
            if let previous = lastCameraPosition, deltaTime > 0 {
                let instant = (position - previous) / deltaTime
                cameraVelocity = cameraVelocity * 0.7 + instant * 0.3
            }
            lastCameraPosition = position

            updateCompassOffset()
            recycleIfBehind(
                forward: SIMD3<Float>(forward.x, 0, forward.z),
                cameraPosition: position)
        }

        if assembly == nil {
            attemptPlacement(allowFallback: true)
        } else if usingFallback {
            // Keep trying to swap the estimated spot for a real floor hit.
            attemptPlacement(allowFallback: false)
        }

        guard let assembly else { return }

        updateOrientation(of: assembly, deltaTime: deltaTime)
        updateMotion(of: assembly)
        if !assembly.coins.isEmpty {
            updateCoins(assembly, deltaTime: deltaTime)
        }
    }

    /// The marker stays pinned to one spot in the room; only its facing
    /// follows the target bearing.
    private func updateOrientation(of assembly: Assembly, deltaTime: Float) {
        let travel = Self.travelDirection(yaw: currentYaw())
        travelUnit = travel
        let desired = Self.orientation(normal: planeNormal, travel: travel)
        let blend = min(1, max(0.08, deltaTime * 6))
        assembly.root.orientation = simd_slerp(assembly.root.orientation, desired, blend)
    }

    /// Minimal motion: a slow float on the whole marker, a wave running through
    /// the trail, and a soft scale-in when the anchor first lands.
    private func updateMotion(of assembly: Assembly) {
        let entrance = min(1, 0.84 + assemblyAge * 1.6)
        assembly.root.scale = SIMD3<Float>(repeating: entrance)

        let float = 0.003 + 0.003 * Float(sin(Double(elapsed) * 1.7))
        assembly.root.position = SIMD3<Float>(0, float, 0)

        for (index, node) in assembly.flow.enumerated() {
            let phase = Double(elapsed) * 1.9 - Double(index) * 0.85
            let wave = 0.78 + 0.22 * (sin(phase) * 0.5 + 0.5)
            node.scale = SIMD3<Float>(repeating: Float(wave))
            node.position.y = 0.004 + 0.004 * Float(max(0, sin(phase)))
        }
    }

    /// Spins the coins, pops the ones the user walks into, and lays down a new
    /// trail once the line is cleared.
    private func updateCoins(_ assembly: Assembly, deltaTime: Float) {
        guard let frame = arView.session.currentFrame else { return }
        let columns = frame.camera.transform.columns
        let camera = SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)

        // A coin only counts when the user is walking the way the arrow points;
        // wandering off (or reversing) must not farm coins.
        let speed = simd_length(cameraVelocity)
        let forwardness = speed > 0.001 ? simd_dot(cameraVelocity / speed, travelUnit) : 0
        let walkingForward = speed > 0.15 && forwardness > 0.55

        // Only the next coin in the line is collectable, so you cannot jump
        // ahead and sweep several at once.
        let nextIndex = assembly.coins.firstIndex {
            $0.parent != nil && coinPickups[ObjectIdentifier($0)] == nil
        }

        for (index, coin) in assembly.coins.enumerated() where coin.parent != nil {
            let key = ObjectIdentifier(coin)

            if let pickedAt = coinPickups[key] {
                let progress = (elapsed - pickedAt) / 0.26
                if progress >= 1 {
                    coin.removeFromParent()
                    coinPickups.removeValue(forKey: key)
                } else {
                    let pop = 1 + 1.6 * progress
                    coin.scale = SIMD3<Float>(repeating: max(0.001, pop * (1 - progress)))
                    coin.position.y += deltaTime * 1.5
                }
                continue
            }

            // Tilt first, then spin about the vertical axis so the face sweeps.
            coin.orientation = simd_quatf(
                angle: elapsed * 2.1 + Float(index), axis: SIMD3<Float>(0, 1, 0)) * Self.coinTilt

            guard walkingForward, index == nextIndex else { continue }

            let world = coin.position(relativeTo: nil)
            let flat = SIMD3<Float>(world.x - camera.x, 0, world.z - camera.z)
            if simd_length(flat) < 0.55, abs(world.y - camera.y) < 1.6 {
                coinPickups[key] = elapsed
                coinsCollected += 1
                coinsRemaining = max(0, coinsRemaining - 1)
                Haptics.impact(.rigid)
            }
        }

        if coinsRemaining == 0, coinPickups.isEmpty, coinsCollected > 0 {
            // Whole line cleared — drop a fresh trail further along.
            clearAssembly()
        }
    }

    /// Keeps a slowly-smoothed mapping between ARKit's world yaw and the
    /// compass. Turning the phone moves both at the same time, so the offset
    /// stays put and the marker keeps pointing at the same spot in the room.
    private func updateCompassOffset() {
        guard headingAvailable else { return }
        // Freeze calibration while the phone is sweeping: the compass lags the
        // camera by a frame or two and would otherwise bend the offset.
        guard compassOffset == nil || turnRate < 0.5 else { return }

        let raw = cameraYaw - Float(deviceHeading * .pi / 180)

        guard let current = compassOffset else {
            compassOffset = raw
            return
        }

        compassOffset = current + shortestAngle(raw - current) * 0.02
    }

    private func shortestAngle(_ angle: Float) -> Float {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }

    /// Fixed world yaw of the travel direction for the current waypoint.
    private func currentYaw() -> Float {
        if let offset = compassOffset {
            return offset + Float(targetBearing * .pi / 180)
        }
        if let frozen = frozenYaw {
            return frozen
        }
        // No compass yet: point along the view direction once and freeze, so
        // the marker still sits still in the world instead of chasing the phone.
        frozenYaw = cameraYaw
        return cameraYaw
    }

    /// Drops the marker once the user has walked past it (or moved far away) so
    /// the next placement lands on the floor ahead again.
    private func recycleIfBehind(forward: SIMD3<Float>, cameraPosition: SIMD3<Float>) {
        guard let assembly else { return }
        let offset = assembly.anchor.position(relativeTo: nil) - cameraPosition
        let flat = SIMD3<Float>(offset.x, 0, offset.z)
        let length = simd_length(flat)
        guard length > 0.3 else { return }
        let facing = simd_dot(simd_normalize(flat), simd_normalize(forward))
        if facing < 0.1 || simd_length(offset) > 6 {
            clearAssembly()
        }
    }

    private func clearAssembly() {
        if let assembly {
            arView.scene.removeAnchor(assembly.anchor)
        }
        assembly = nil
        coinPickups.removeAll()
        coinsRemaining = 0
        usingFallback = false
        planeNormal = SIMD3<Float>(0, 1, 0)
        lastAttempt = -10
        searchStartedAt = elapsed
        status = .searching
    }

    // MARK: - Placement

    /// Raycasts a few screen points until the floor (or a wall) in front of the
    /// user is found, then anchors the content there. Points below the centre
    /// aim the ray at the floor; the centre point catches walls.
    private func attemptPlacement(allowFallback: Bool) {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard elapsed - lastAttempt > 0.1 else { return }
        lastAttempt = elapsed
        guard let frame = arView.session.currentFrame else { return }

        let columns = frame.camera.transform.columns
        let cameraPosition = SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
        let forward = SIMD3<Float>(-columns.2.x, 0, -columns.2.z)

        let probes = [
            CGPoint(x: bounds.midX, y: bounds.height * 0.78),
            CGPoint(x: bounds.midX, y: bounds.height * 0.66),
            CGPoint(x: bounds.midX, y: bounds.height * 0.90)
        ]

        for probe in probes {
            guard let hit = arView.raycast(
                from: probe, allowing: .estimatedPlane, alignment: .any).first else { continue }

            let transform = hit.worldTransform
            let position = SIMD3<Float>(
                transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let distance = simd_length(position - cameraPosition)
            guard distance > 0.5, distance < 12 else { continue }

            var normal = simd_normalize(SIMD3<Float>(
                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
            if simd_dot(normal, simd_normalize(cameraPosition - position)) < 0 {
                normal = -normal
            }

            place(at: position, normal: normal,
                  alignment: abs(normal.y) > 0.72 ? .floor : .wall,
                  fallback: false)
            return
        }

        // Nothing recognisable yet (big open concourse, phone held level) —
        // drop a provisional marker on the estimated floor so guidance still shows.
        if allowFallback, elapsed - searchStartedAt > 2.0 {
            let direction = simd_length(forward) < 0.001 ? SIMD3<Float>(0, 0, 1) : simd_normalize(forward)
            let position = cameraPosition + direction * 1.6 - SIMD3<Float>(0, 1.45, 0)
            place(at: position, normal: SIMD3<Float>(0, 1, 0), alignment: .floor, fallback: true)
        }
    }

    private func place(
        at position: SIMD3<Float>,
        normal: SIMD3<Float>,
        alignment: Alignment,
        fallback: Bool
    ) {
        clearAssembly()

        var world = matrix_identity_float4x4
        world.columns.3 = SIMD4<Float>(position + normal * 0.012, 1)

        let anchor = AnchorEntity(world: world)
        let content = makeContent()
        anchor.addChild(content.root)
        arView.scene.addAnchor(anchor)

        assembly = Assembly(
            anchor: anchor,
            root: content.root,
            body: content.body,
            flow: content.flow,
            coins: content.coins)
        planeNormal = normal
        usingFallback = fallback
        assemblyAge = 0
        coinsRemaining = content.coins.count
        status = .placed(alignment)
    }

    // MARK: - Content

    private func makeContent() -> (root: Entity, body: Entity, flow: [Entity], coins: [ModelEntity]) {
        let root = Entity()

        if gameMode {
            // Minimal coin line: walk through them, they pop.
            var coins: [ModelEntity] = []
            for index in 0..<8 {
                let coin = ModelEntity(mesh: Self.coinMesh, materials: [Self.coinMaterial()])
                coin.position = SIMD3<Float>(0, 0.32, 0.55 + Float(index) * 0.55)
                coin.orientation = Self.coinTilt
                root.addChild(coin)
                coins.append(coin)
            }
            return (root, Entity(), [], coins)
        }

        let body = Entity()
        let material = Self.arrowMaterial()
        body.addChild(ModelEntity(mesh: Self.arrowHeadMesh, materials: [material]))
        let tail = ModelEntity(mesh: Self.arrowTailMesh, materials: [material])
        // Sunk a hair so the head wins the shared area without z-fighting.
        tail.position = SIMD3<Float>(0, -0.001, 0)
        body.addChild(tail)
        root.addChild(body)

        var flow: [Entity] = []
        for index in 0..<3 {
            let dash = ModelEntity(mesh: Self.dashMesh, materials: [Self.dashMaterial()])
            dash.position = SIMD3<Float>(0, 0.004, 1.04 + Float(index) * 0.32)
            root.addChild(dash)
            flow.append(dash)
        }
        return (root, body, flow, [])
    }

    // MARK: - Geometry

    private static func travelDirection(yaw: Float) -> SIMD3<Float> {
        SIMD3<Float>(Float(sin(Double(yaw))), 0, Float(cos(Double(yaw))))
    }

    /// Builds an orientation whose +Z axis follows `travel` while its +Y axis
    /// matches the surface normal — flat on the floor, flush against a wall.
    private static func orientation(normal: SIMD3<Float>, travel: SIMD3<Float>) -> simd_quatf {
        let up = simd_normalize(normal)
        var forward = travel - up * simd_dot(travel, up)
        if simd_length(forward) < 0.001 {
            forward = SIMD3<Float>(0, 0, 1) - up * up.z
            if simd_length(forward) < 0.001 {
                forward = SIMD3<Float>(1, 0, 0) - up * up.x
            }
        }
        forward = simd_normalize(forward)
        let right = simd_normalize(simd_cross(up, forward))
        return simd_quatf(simd_float3x3(columns: (right, up, forward)))
    }

    private static let tiltAxis = SIMD3<Float>(1, 0, 0)
    private static let coinTilt = simd_quatf(angle: .pi / 2, axis: tiltAxis)

    /// Slim arrow built from two convex plates: a rounded triangle head and a
    /// capsule tail (fan triangulation only works on convex outlines).
    private static let arrowHeadMesh = extruded(
        outline: roundedOutline(
            [SIMD2(-0.26, 0.42), SIMD2(0.26, 0.42), SIMD2(0.00, 0.86)],
            radius: 0.07),
        thickness: 0.008)

    private static let arrowTailMesh = extruded(
        outline: roundedOutline(
            [SIMD2(-0.10, 0.00), SIMD2(0.10, 0.00), SIMD2(0.10, 0.44), SIMD2(-0.10, 0.44)],
            radius: 0.09),
        thickness: 0.008)

    /// Short capsule used for the flowing trail.
    private static let dashMesh = extruded(
        outline: roundedOutline(
            [SIMD2(-0.05, 0.00), SIMD2(0.05, 0.00), SIMD2(0.05, 0.17), SIMD2(-0.05, 0.17)],
            radius: 0.045),
        thickness: 0.006)

    /// Coin as a thin disc (cylinders need iOS 18, so the disc is extruded).
    private static let coinMesh = extruded(
        outline: discOutline(radius: 0.082, segments: 28),
        thickness: 0.012)

    private static func discOutline(radius: Float, segments: Int) -> [SIMD2<Float>] {
        (0..<segments).map { index in
            let angle = Double(index) / Double(segments) * 2 * Double.pi
            return SIMD2<Float>(
                Float(cos(angle)) * radius,
                Float(sin(angle)) * radius)
        }
    }

    private static func arrowMaterial() -> PhysicallyBasedMaterial {
        minimalMaterial(
            tint: UIColor(red: 0.94, green: 0.20, blue: 0.30, alpha: 1),
            roughness: 0.45,
            metallic: 0.0,
            emission: 0.35)
    }

    private static func dashMaterial() -> PhysicallyBasedMaterial {
        minimalMaterial(
            tint: UIColor(red: 0.97, green: 0.52, blue: 0.56, alpha: 1),
            roughness: 0.6,
            metallic: 0.0,
            emission: 0.25)
    }

    private static func coinMaterial() -> PhysicallyBasedMaterial {
        minimalMaterial(
            tint: UIColor(red: 1.00, green: 0.79, blue: 0.35, alpha: 1),
            roughness: 0.24,
            metallic: 0.9,
            emission: 0.3)
    }

    private static func minimalMaterial(
        tint: UIColor, roughness: Float, metallic: Float, emission: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.emissiveColor = .init(color: tint.withAlphaComponent(CGFloat(emission)))
        material.emissiveIntensity = 0.7
        // Thin plates are seen from every angle; culling off keeps them solid.
        material.faceCulling = .none
        return material
    }

    /// Replaces every corner of a convex outline with a quadratic curve.
    private static func roundedOutline(
        _ corners: [SIMD2<Float>], radius: Float, segments: Int = 6
    ) -> [SIMD2<Float>] {
        var result: [SIMD2<Float>] = []
        let count = corners.count
        guard count >= 3 else { return corners }

        for index in 0..<count {
            let corner = corners[index]
            let previous = corners[(index + count - 1) % count]
            let next = corners[(index + 1) % count]

            let toPrevious = previous - corner
            let toNext = next - corner
            let lengthPrevious = simd_length(toPrevious)
            let lengthNext = simd_length(toNext)
            guard lengthPrevious > 0.0001, lengthNext > 0.0001 else {
                result.append(corner)
                continue
            }

            let r = min(radius, min(lengthPrevious, lengthNext) * 0.49)
            let start = corner + simd_normalize(toPrevious) * r
            let end = corner + simd_normalize(toNext) * r

            for step in 0...segments {
                let t = Float(step) / Float(segments)
                let inverse = 1 - t
                result.append(
                    start * (inverse * inverse)
                        + corner * (2 * inverse * t)
                        + end * (t * t))
            }
        }
        return result
    }

    /// Extrudes a convex outline (in the XZ plane, pointing +Z) into a prism.
    private static func extruded(outline raw: [SIMD2<Float>], thickness: Float) -> MeshResource {
        var outline = raw
        if signedArea(outline) < 0 { outline.reverse() }

        let half = thickness / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func addTriangle(
            _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>,
            y: Float, normal: SIMD3<Float>
        ) {
            let base = UInt32(positions.count)
            positions.append(SIMD3<Float>(a.x, y, a.y))
            positions.append(SIMD3<Float>(b.x, y, b.y))
            positions.append(SIMD3<Float>(c.x, y, c.y))
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        // Convex outline: a fan from the first vertex covers both caps.
        let up = SIMD3<Float>(0, 1, 0)
        let down = SIMD3<Float>(0, -1, 0)
        for index in 1..<(outline.count - 1) {
            addTriangle(outline[0], outline[index], outline[index + 1], y: half, normal: up)
            addTriangle(outline[0], outline[index + 1], outline[index], y: -half, normal: down)
        }

        for index in 0..<outline.count {
            let a = outline[index]
            let b = outline[(index + 1) % outline.count]
            let edge = SIMD2<Float>(b.x - a.x, b.y - a.y)
            let length = sqrt(edge.x * edge.x + edge.y * edge.y)
            guard length > 0.0001 else { continue }
            let normal = SIMD3<Float>(edge.y / length, 0, -edge.x / length)

            let base = UInt32(positions.count)
            positions.append(SIMD3<Float>(a.x, half, a.y))
            positions.append(SIMD3<Float>(b.x, half, b.y))
            positions.append(SIMD3<Float>(b.x, -half, b.y))
            positions.append(SIMD3<Float>(a.x, -half, a.y))
            normals.append(contentsOf: [normal, normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "guideArrow")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)

        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generateBox(size: SIMD3<Float>(0.2, thickness, 0.86))
    }

    private static func signedArea(_ outline: [SIMD2<Float>]) -> Float {
        var total: Float = 0
        for index in 0..<outline.count {
            let current = outline[index]
            let next = outline[(index + 1) % outline.count]
            total += current.x * next.y - next.x * current.y
        }
        return total / 2
    }
}

// MARK: - ARSessionDelegate

extension ARGuideController: ARSessionDelegate {

    func session(_ session: ARSession, didFailWithError error: Error) {
        let code = (error as? ARError)?.code
        DispatchQueue.main.async {
            self.failure = code == .cameraUnauthorized ? .cameraDenied : .interrupted(error.localizedDescription)
            self.assembly = nil
            self.status = .searching
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            guard self.running else { return }
            self.start()
        }
    }
}

// MARK: - SwiftUI bridge

/// Hosts the AR view. Only used when `ARWorldTrackingConfiguration` is
/// supported; the plain camera preview stays as the simulator fallback.
struct ARGuidanceScene: UIViewRepresentable {
    @ObservedObject var guide: ARGuideController

    func makeUIView(context: Context) -> ARView {
        guide.start()
        return guide.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        uiView.session.pause()
    }
}
