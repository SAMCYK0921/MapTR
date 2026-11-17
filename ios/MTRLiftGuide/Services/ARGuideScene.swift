//
//  ARGuideScene.swift
//  MTR Lift Guide
//
//  Real augmented reality for the guidance screen. An ARKit world-tracking
//  session maps the station floor / walls, and a RealityKit arrow is anchored
//  onto whichever surface is in front of the phone. The arrow always points at
//  the compass bearing of the current waypoint, so it stays pinned to the real
//  world while the phone turns — instead of being a 2D sticker over the feed.
//

import ARKit
import Combine
import RealityKit
import SwiftUI
import UIKit
import simd

/// Owns the `ARView`, its session and the anchored arrow.
final class ARGuideController: NSObject, ObservableObject {

    /// Which surface the arrow landed on.
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

    let arView: ARView

    private var anchor: AnchorEntity?
    private var arrow: Entity?
    private var planeNormal = SIMD3<Float>(0, 1, 0)

    private var targetBearing: Double = 0
    private var deviceHeading: Double = 0
    private var headingAvailable = false

    private var cameraYaw: Float = 0
    private var elapsed: Float = 0
    private var lastAttempt: Float = -10
    private var searchStartedAt: Float = 0
    private var usingFallback = false
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
    /// added when the device supports it so the arrow hides behind furniture.
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

        clearArrow()
        failure = nil
        running = true
        arView.session.run(makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        running = false
        arView.session.pause()
    }

    /// Drop the current arrow and map the surroundings again.
    func recenter() {
        guard running else {
            start()
            return
        }
        clearArrow()
        failure = nil
        arView.session.run(makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Guidance input

    func setTarget(bearing: Double) {
        targetBearing = bearing
    }

    func setHeading(_ heading: Double, available: Bool) {
        deviceHeading = heading
        headingAvailable = available
    }

    // MARK: - Frame loop

    private func tick(deltaTime: Float) {
        guard running else { return }
        elapsed += deltaTime

        if let frame = arView.session.currentFrame {
            let columns = frame.camera.transform.columns
            let forward = -columns.2
            cameraYaw = Float(atan2(Double(forward.x), Double(forward.z)))
            recycleIfBehind(
                forward: SIMD3<Float>(forward.x, 0, forward.z),
                cameraPosition: SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z))
        }

        if anchor == nil {
            attemptPlacement(allowFallback: true)
        } else if usingFallback {
            // Keep trying to swap the estimated spot for a real floor hit.
            attemptPlacement(allowFallback: false)
        }

        guard let arrow else { return }

        let travel = Self.travelDirection(yaw: currentYaw())
        let desired = Self.orientation(normal: planeNormal, travel: travel)
        let blend = min(1, max(0.08, deltaTime * 6))
        arrow.orientation = simd_slerp(arrow.orientation, desired, blend)

        let pulse = 1 + 0.03 * Float(sin(Double(elapsed) * 2.4))
        arrow.scale = SIMD3<Float>(repeating: pulse)
    }

    /// World yaw of the travel direction: camera yaw plus the signed difference
    /// between where the phone faces and where the waypoint bearing points.
    private func currentYaw() -> Float {
        let delta = headingAvailable ? (deviceHeading - targetBearing) : 0
        return cameraYaw + Float(delta * .pi / 180)
    }

    /// Drops the arrow once the user has walked past it (or moved far away) so
    /// the next placement lands on the floor ahead again.
    private func recycleIfBehind(forward: SIMD3<Float>, cameraPosition: SIMD3<Float>) {
        guard let anchor else { return }
        let offset = anchor.position(relativeTo: nil) - cameraPosition
        let flat = SIMD3<Float>(offset.x, 0, offset.z)
        let length = simd_length(flat)
        guard length > 0.3 else { return }
        let facing = simd_dot(simd_normalize(flat), simd_normalize(forward))
        if facing < 0.1 || simd_length(offset) > 6 {
            clearArrow()
        }
    }

    private func clearArrow() {
        if let anchor {
            arView.scene.removeAnchor(anchor)
        }
        anchor = nil
        arrow = nil
        usingFallback = false
        planeNormal = SIMD3<Float>(0, 1, 0)
        lastAttempt = -10
        searchStartedAt = elapsed
        status = .searching
    }

    // MARK: - Placement

    /// Raycasts a few screen points until the floor (or a wall) in front of the
    /// user is found, then anchors the arrow there. Points below the centre aim
    /// the ray at the floor; the centre point catches walls.
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
        // drop a provisional arrow on the estimated floor so guidance still shows.
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
        clearArrow()

        var world = matrix_identity_float4x4
        world.columns.3 = SIMD4<Float>(position + normal * 0.012, 1)

        let anchor = AnchorEntity(world: world)
        let arrow = Self.makeArrow()
        arrow.orientation = Self.orientation(
            normal: normal, travel: Self.travelDirection(yaw: currentYaw()))
        anchor.addChild(arrow)
        arView.scene.addAnchor(anchor)

        self.anchor = anchor
        self.arrow = arrow
        self.planeNormal = normal
        self.usingFallback = fallback
        self.status = .placed(alignment)
    }

    // MARK: - Geometry helpers

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

    /// Flat arrow lying in the entity's local XZ plane, tip pointing +Z.
    /// One extruded piece with real thickness, plus a fading trail of smaller
    /// arrows so the direction reads as a path instead of a pasted sticker.
    private static func makeArrow() -> Entity {
        let root = Entity()

        let body = ModelEntity(mesh: arrowMesh(), materials: [arrowMaterial(
            tint: UIColor(red: 0.90, green: 0.11, blue: 0.24, alpha: 1))])
        root.addChild(body)

        for index in 0..<3 {
            let trail = ModelEntity(mesh: arrowMesh(), materials: [arrowMaterial(
                tint: UIColor(red: 0.95, green: 0.35, blue: 0.42, alpha: 1))])
            trail.scale = SIMD3<Float>(repeating: 0.34 - Float(index) * 0.06)
            trail.position = SIMD3<Float>(0, 0, 1.16 + Float(index) * 0.36)
            root.addChild(trail)
        }

        return root
    }

    /// Solid, light-reactive red so the arrow picks up the station lighting
    /// instead of looking like a flat cut-out.
    private static func arrowMaterial(tint: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.roughness = 0.34
        material.metallic = 0.05
        material.emissiveColor = .init(color: tint.withAlphaComponent(0.45))
        material.emissiveIntensity = 0.65
        // The mesh supplies both faces; culling off keeps it visible from any
        // angle while the user walks around it.
        material.faceCulling = .none
        return material
    }

    /// Extrudes the arrow outline (tip at +Z) into a single watertight mesh.
    private static func arrowMesh() -> MeshResource {
        let thickness: Float = 0.024
        let half = thickness / 2

        // Outline in the XZ plane.
        let outline: [SIMD2<Float>] = [
            SIMD2(0.00, 0.94),   // tip
            SIMD2(0.31, 0.48),   // right head corner
            SIMD2(0.12, 0.48),   // right shoulder
            SIMD2(0.12, 0.00),   // right tail
            SIMD2(-0.12, 0.00),  // left tail
            SIMD2(-0.12, 0.48),  // left shoulder
            SIMD2(-0.31, 0.48)   // left head corner
        ]

        // Head triangle plus the two shaft triangles.
        let faces: [(Int, Int, Int)] = [(0, 1, 6), (2, 3, 4), (2, 4, 5)]

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

        for (i, j, k) in faces {
            addTriangle(outline[i], outline[j], outline[k], y: half, normal: SIMD3<Float>(0, 1, 0))
            addTriangle(outline[i], outline[k], outline[j], y: -half, normal: SIMD3<Float>(0, -1, 0))
        }

        for i in 0..<outline.count {
            let a = outline[i]
            let b = outline[(i + 1) % outline.count]
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
            ?? MeshResource.generateBox(size: SIMD3<Float>(0.24, thickness, 0.94))
    }
}

// MARK: - ARSessionDelegate

extension ARGuideController: ARSessionDelegate {

    func session(_ session: ARSession, didFailWithError error: Error) {
        let code = (error as? ARError)?.code
        DispatchQueue.main.async {
            self.failure = code == .cameraUnauthorized ? .cameraDenied : .interrupted(error.localizedDescription)
            self.arrow = nil
            self.anchor = nil
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
