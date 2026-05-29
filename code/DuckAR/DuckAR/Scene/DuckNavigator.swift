//
//  DuckNavigator.swift
//  DuckAR
//
//  Per-frame interpolation toward DuckBehaviorCoordinator's target position.
//  Drives a free world-space AnchorEntity (DuckEntityCoordinator owns the
//  reparenting so we don't touch ARSession). Y is locked to the ground plane
//  where the duck spawned — perception targets that suggest a different height
//  (e.g. a chair seat raycast) are flattened to ground.
//
//  Motion polish lives in DuckMotionConfig so a single struct holds every
//  tunable knob (speed, ease durations, idle cadence, look-around).
//

import ARKit
import Combine
import Foundation
import QuartzCore
import RealityKit
import simd

struct DuckMotionConfig {
    // Walk — a mallard waddle is slow and deliberate.
    var baseSpeed: Float = 0.18
    // ~143°/s: brisk enough to re-aim, slow enough to read as a body turn
    // rather than an instant heading snap.
    var rotationSpeed: Float = 2.5
    var idleRotationSpeed: Float = 1.5
    var arrivalThreshold: Float = 0.05
    var forwardAxisOffset: Float = 0          // USDZ mesh-forward correction

    // Ease-in / ease-out around the walk
    var accelDuration: TimeInterval = 0.5
    var decelDuration: TimeInterval = 0.4
    // Heading error at/above which forward speed is fully gated to zero (the
    // duck pivots in place). Below it, forward speed scales smoothly with
    // alignment so re-aiming blends into walking instead of a hard stop/start.
    var turnFirstThreshold: Float = .pi / 4   // 45°

    // Camera-distance driven scale
    var scaleMin: Float = 0.7
    var scaleMax: Float = 1.8
    var scaleReferenceDistance: Float = 1.0
    var scaleLerpRatePerSec: Float = 0.2

    // Respawn when out of useful view
    var respawnMaxDistance: Float = 4.0
    var respawnPlacementDistance: Float = 1.0

    // Idle drift — quiet random look while no target
    var idleLookInterval: ClosedRange<TimeInterval> = 5.0...10.0
    var idleLookYawRange: Float = .pi / 6     // ±30°
    var idleLookDuration: TimeInterval = 1.5

    // Look-around immediately after arrival
    var arrivedDwellDuration: ClosedRange<TimeInterval> = 2.0...4.0
    var arrivedLookYawRange: Float = .pi / 6  // ±30°

    // Bobbing — USDZ walk cycle usually provides Y oscillation; leave at 0.
    var bobbingAmplitude: Float = 0
    var bobbingFrequency: Float = 0
}

@MainActor
final class DuckNavigator {

    let config = DuckMotionConfig()

    weak var debugLog: DebugLogStore?

    private weak var anchor: AnchorEntity?
    private weak var arView: ARView?
    // Owned by DuckEntityCoordinator; supplies metric-depth walkability. nil
    // until depth frames flow — navigation then runs plane-only as before.
    private var depthField: DepthNavigationField?
    private var groundY: Float = 0
    private var target: SIMD3<Float>?
    private var hasArrived = false

    // Phase tracking
    private var motionStartTime: TimeInterval?
    private var idleLook: IdleLook?
    private var nextIdleLookAt: TimeInterval?

    private var targetSubscription: AnyCancellable?
    private var updateSubscription: Cancellable?

    private struct IdleLook {
        let targetYaw: Float
        let endsAt: TimeInterval
        let source: String   // "arrived" or "idle-drift" — for debug log
    }

    func attach(
        anchor: AnchorEntity,
        arView: ARView,
        groundY: Float,
        scene: RealityKit.Scene,
        targetPublisher: AnyPublisher<SIMD3<Float>?, Never>,
        depthField: DepthNavigationField? = nil
    ) {
        self.anchor = anchor
        self.arView = arView
        self.groundY = groundY
        self.depthField = depthField

        targetSubscription = targetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTarget in
                Task { @MainActor [weak self] in
                    self?.setTarget(newTarget)
                }
            }

        updateSubscription = scene.subscribe(
            to: SceneEvents.Update.self
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.step(deltaTime: Float(event.deltaTime))
            }
        }
    }

    func detach() {
        targetSubscription?.cancel()
        targetSubscription = nil
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    private func setTarget(_ newTarget: SIMD3<Float>?) {
        guard let anchor else { return }
        guard let newTarget else {
            target = nil
            return
        }
        let locked = SIMD3<Float>(newTarget.x, groundY, newTarget.z)
        target = locked
        hasArrived = false
        idleLook = nil
        nextIdleLookAt = nil
        motionStartTime = nil

        let dist = simd_distance(anchor.position, locked)
        debugLog?.log(
            .nav,
            String(format: "🦆 nav → (%.2f, %.2f, %.2f) dist=%.2f",
                   locked.x, locked.y, locked.z, dist)
        )
    }

    private func step(deltaTime: Float) {
        guard let anchor, let arView else { return }

        if shouldRespawn(arView: arView, anchor: anchor) {
            respawn(arView: arView, anchor: anchor)
            return
        }

        applyScale(arView: arView, anchor: anchor, deltaTime: deltaTime)

        let now = CACurrentMediaTime()

        if let target, !hasArrived {
            navigateToward(target: target, anchor: anchor, now: now, deltaTime: deltaTime)
        } else {
            runIdle(anchor: anchor, now: now, deltaTime: deltaTime)
        }
    }

    private func navigateToward(
        target: SIMD3<Float>,
        anchor: AnchorEntity,
        now: TimeInterval,
        deltaTime: Float
    ) {
        let current = anchor.position
        let delta = target - current
        let distance = simd_length(delta)

        // Depth-gated reach: clamp how far the duck may advance toward the
        // target this frame so it stops in front of real obstacles (and can
        // still aim at floor between/behind furniture where a plane raycast
        // found nothing). Fail-open to `distance` when depth is unavailable.
        let walkable = depthField?.walkableDistance(
            from: current, to: target, groundY: groundY
        ) ?? distance
        let goalDistance = min(distance, walkable)

        if goalDistance < config.arrivalThreshold {
            if distance > config.arrivalThreshold {
                debugLog?.log(.nav, "🦆 blocked — stopping short of target")
            }
            onArrived(anchor: anchor, now: now)
            return
        }

        let direction = delta / distance
        let desiredYaw = atan2(direction.x, direction.z) + config.forwardAxisOffset
        let currentYaw = Self.yaw(of: anchor.orientation)
        let yawDelta = Self.shortestAngleDelta(from: currentYaw, to: desiredYaw)
        let absYaw = abs(yawDelta)

        // Rotate every frame toward the target heading. Clamping by maxYawStep
        // naturally eases the turn out as |yawDelta| drops below one frame's
        // worth of rotation, so the heading settles rather than overshooting.
        let maxYawStep = config.rotationSpeed * deltaTime
        let yawStep = max(-maxYawStep, min(maxYawStep, yawDelta))
        anchor.orientation = simd_quatf(
            angle: currentYaw + yawStep,
            axis: SIMD3<Float>(0, 1, 0)
        )

        // Alignment-gated forward speed: 1 when aimed at the target, ramping
        // smoothly to 0 at turnFirstThreshold (and beyond). This replaces the
        // old binary hold — large turns pivot in place, moderate turns walk a
        // gentle arc, and there is no velocity discontinuity at the boundary.
        let alignment = 1 - smoothstep01(absYaw / config.turnFirstThreshold)
        if alignment <= 0.001 {
            // Effectively pivoting in place; pause the accel ramp so the next
            // step out of the turn eases in from rest.
            motionStartTime = nil
            return
        }

        // Ease-in from motionStartTime over accelDuration.
        if motionStartTime == nil {
            motionStartTime = now
            debugLog?.log(.nav, "🦆 accel")
        }
        let elapsed = Float(now - (motionStartTime ?? now))
        let easeIn = smoothstep01(elapsed / Float(config.accelDuration))

        // Ease-out within the last `baseSpeed * decelDuration` meters of the
        // reachable goal (target or depth-clamped stop point).
        let decelDistance = config.baseSpeed * Float(config.decelDuration)
        let easeOut: Float
        if decelDistance > 0, goalDistance < decelDistance {
            easeOut = smoothstep01(goalDistance / decelDistance)
        } else {
            easeOut = 1.0
        }

        let effectiveSpeed = config.baseSpeed * easeIn * easeOut * alignment
        let stepLength = min(effectiveSpeed * deltaTime, goalDistance)
        anchor.position = current + direction * stepLength
    }

    private func onArrived(anchor: AnchorEntity, now: TimeInterval) {
        hasArrived = true
        motionStartTime = nil
        debugLog?.log(.nav, "🦆 arrived")

        // Schedule the post-arrival look-around as the immediate idle action.
        let dwell = Double.random(in: config.arrivedDwellDuration)
        let dyaw = Float.random(in: -config.arrivedLookYawRange...config.arrivedLookYawRange)
        let currentYaw = Self.yaw(of: anchor.orientation)
        idleLook = IdleLook(
            targetYaw: currentYaw + dyaw,
            endsAt: now + dwell,
            source: "arrived"
        )
        debugLog?.log(.nav, String(format: "🦆 idle look (%@) Δyaw=%.2f", "arrived", dyaw))
    }

    private func runIdle(anchor: AnchorEntity, now: TimeInterval, deltaTime: Float) {
        if let look = idleLook {
            let currentYaw = Self.yaw(of: anchor.orientation)
            let yawDelta = Self.shortestAngleDelta(from: currentYaw, to: look.targetYaw)
            let maxYawStep = config.idleRotationSpeed * deltaTime
            let yawStep = max(-maxYawStep, min(maxYawStep, yawDelta))
            anchor.orientation = simd_quatf(
                angle: currentYaw + yawStep,
                axis: SIMD3<Float>(0, 1, 0)
            )
            if now >= look.endsAt {
                idleLook = nil
                scheduleNextIdleLook(from: now)
            }
            return
        }

        if let scheduled = nextIdleLookAt {
            if now >= scheduled {
                let dyaw = Float.random(in: -config.idleLookYawRange...config.idleLookYawRange)
                let currentYaw = Self.yaw(of: anchor.orientation)
                idleLook = IdleLook(
                    targetYaw: currentYaw + dyaw,
                    endsAt: now + config.idleLookDuration,
                    source: "idle-drift"
                )
                nextIdleLookAt = nil
                debugLog?.log(.nav, String(format: "🦆 idle look (%@) Δyaw=%.2f", "drift", dyaw))
            }
        } else {
            scheduleNextIdleLook(from: now)
        }
    }

    private func scheduleNextIdleLook(from now: TimeInterval) {
        let interval = Double.random(in: config.idleLookInterval)
        nextIdleLookAt = now + interval
    }

    private func applyScale(arView: ARView, anchor: AnchorEntity, deltaTime: Float) {
        let cameraPos = Self.cameraPosition(arView: arView)
        let distance = simd_distance(cameraPos, anchor.position)
        let raw = distance / config.scaleReferenceDistance
        let target = max(config.scaleMin, min(config.scaleMax, raw))
        let current = anchor.scale.x
        let maxStep = config.scaleLerpRatePerSec * deltaTime
        let stepDelta = target - current
        let clamped = max(-maxStep, min(maxStep, stepDelta))
        anchor.scale = SIMD3<Float>(repeating: current + clamped)
    }

    private func shouldRespawn(arView: ARView, anchor: AnchorEntity) -> Bool {
        let cameraPos = Self.cameraPosition(arView: arView)
        let cameraForward = Self.cameraForward(arView: arView)
        let duckPos = anchor.position

        if simd_distance(cameraPos, duckPos) > config.respawnMaxDistance { return true }
        if simd_dot(cameraForward, duckPos - cameraPos) < 0 { return true }
        guard let screenPoint = arView.project(duckPos) else { return true }
        if !arView.bounds.contains(screenPoint) { return true }
        return false
    }

    private func respawn(arView: ARView, anchor: AnchorEntity) {
        let cameraPos = Self.cameraPosition(arView: arView)
        let cameraForward = Self.cameraForward(arView: arView)

        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let newPos: SIMD3<Float>
        if let hit = arView.raycast(
            from: screenCenter,
            allowing: .existingPlaneInfinite,
            alignment: .horizontal
        ).first {
            let t = hit.worldTransform.columns.3
            newPos = SIMD3<Float>(t.x, t.y, t.z)
            groundY = newPos.y
        } else {
            let ahead = cameraPos + cameraForward * config.respawnPlacementDistance
            newPos = SIMD3<Float>(ahead.x, groundY, ahead.z)
        }
        anchor.position = newPos
        hasArrived = false
        motionStartTime = nil
        idleLook = nil
        nextIdleLookAt = nil

        debugLog?.log(
            .nav,
            String(format: "🦆 respawn → (%.2f, %.2f, %.2f)", newPos.x, newPos.y, newPos.z)
        )
    }

    private static func cameraPosition(arView: ARView) -> SIMD3<Float> {
        let c = arView.cameraTransform.matrix.columns.3
        return SIMD3<Float>(c.x, c.y, c.z)
    }

    // ARKit camera looks down its local -Z axis; world-space forward is the
    // negation of column 2 of the camera transform.
    private static func cameraForward(arView: ARView) -> SIMD3<Float> {
        let c = arView.cameraTransform.matrix.columns.2
        return SIMD3<Float>(-c.x, -c.y, -c.z)
    }

    // Extracts Y-axis yaw from a unit quaternion. Assumes the anchor is only
    // ever rotated around Y (we never set pitch/roll), so a full Tait-Bryan
    // decomposition isn't needed.
    private static func yaw(of q: simd_quatf) -> Float {
        let r = q.vector
        let sinyCosp = 2 * (r.w * r.y + r.x * r.z)
        let cosyCosp = 1 - 2 * (r.y * r.y + r.x * r.x)
        return atan2(sinyCosp, cosyCosp)
    }

    private static func shortestAngleDelta(from a: Float, to b: Float) -> Float {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

private func smoothstep01(_ x: Float) -> Float {
    let t = max(0, min(1, x))
    return t * t * (3 - 2 * t)
}
