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
            attemptPlacement()
        }

        guard let arrow else { return }

        let travel = Self.travelDirection(yaw: currentYaw())
        let desired = Self.orientation(normal: planeNormal, travel: travel)
        let blend = min(1, max(0.08, deltaTime * 6))
        arrow.orientation = simd_slerp(arrow.orientation, desired, blend)

        let pulse = 1 + 0.05 * Float(sin(Double(elapsed) * 3.2))
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
        planeNormal = SIMD3<Float>(0, 1, 0)
        lastAttempt = -10
        status = .searching
    }

    // MARK: - Placement

    /// Raycasts a few screen points until the floor (or a wall) in front of the
    /// user is found, then anchors the arrow there. Points below the centre aim
    /// the ray at the floor; the centre point catches walls.
    private func attemptPlacement() {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard elapsed - lastAttempt > 0.1 else { return }
        lastAttempt = elapsed
        guard let frame = arView.session.currentFrame else { return }

        let cameraPosition = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z)

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
            guard distance > 0.5, distance < 9 else { continue }

            var normal = simd_normalize(SIMD3<Float>(
                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
            if simd_dot(normal, simd_normalize(cameraPosition - position)) < 0 {
                normal = -normal
            }

            place(at: position, normal: normal,
                  alignment: abs(normal.y) > 0.72 ? .floor : .wall)
            return
        }
    }

    private func place(at position: SIMD3<Float>, normal: SIMD3<Float>, alignment: Alignment) {
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
    private static func makeArrow() -> Entity {
        let root = Entity()

        var body = UnlitMaterial()
        body.color = .init(tint: UIColor(red: 0.93, green: 0.16, blue: 0.30, alpha: 1))

        var trail = UnlitMaterial()
        trail.color = .init(tint: UIColor(red: 0.93, green: 0.42, blue: 0.48, alpha: 1))

        let shaft = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.20, 0.014, 0.56), cornerRadius: 0.006),
            materials: [body])
        shaft.position = SIMD3<Float>(0, 0, 0.28)
        root.addChild(shaft)

        // Arrow head built from two blades meeting at the tip (z ≈ 0.82).
        for side in [Float(-1), Float(1)] {
            let blade = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.10, 0.014, 0.36), cornerRadius: 0.005),
                materials: [body])
            blade.position = SIMD3<Float>(side * 0.09, 0.004, 0.66)
            blade.orientation = simd_quatf(
                angle: -side * 0.54, axis: SIMD3<Float>(0, 1, 0))
            root.addChild(blade)
        }

        for index in 0..<3 {
            let dash = ModelEntity(
                mesh: .generateBox(
                    size: SIMD3<Float>(0.09, 0.010, 0.16), cornerRadius: 0.004),
                materials: [trail])
            dash.position = SIMD3<Float>(0, 0, 1.00 + Float(index) * 0.30)
            dash.scale = SIMD3<Float>(repeating: 1 - Float(index) * 0.14)
            root.addChild(dash)
        }

        return root
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
