import Foundation
import CoreGraphics

@main struct EnhancementChecks {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError("FAIL: \(label)") }
            count += 1; print("PASS: \(label)")
        }
        let defaults = PetEnhancements()
        check(defaults.fullBody && defaults.idleMotion && defaults.inertia, "enhancements default on")
        check(defaults.articulatedMotion, "layered animation enabled by default")
        check(!PetEnhancements(values:["articulatedMotion":false]).articulatedMotion, "previous illustration remains selectable")
        check(!defaults.clickThrough && !defaults.positionLocked, "interaction accessible by default")
        check(defaults.opacity == 1, "fully visible by default")
        check(defaults.performance == .balanced, "balanced default")
        check(defaults.fullBodyStyle == .winged, "reference-inspired winged style is default")
        check(PetEnhancements(values: ["fullBody": true]).fullBodyStyle == .winged, "older preferences adopt new style")
        check(PetEnhancements(values: ["fullBodyStyle": "unknown"]).fullBodyStyle == .winged, "invalid style fallback")
        var chibi = defaults; chibi.fullBodyStyle = .chibi
        check(PetEnhancements(values: chibi.values).fullBodyStyle == .chibi, "previous chibi style remains selectable")
        check(PetFullBodyStyle.winged.assetName != PetFullBodyStyle.chibi.assetName, "new asset never overwrites original")
        check(defaults.canvasSize == CGSize(width: 378, height: 490), "full-body canvas includes feet")
        var bust = defaults; bust.fullBody = false
        check(bust.canvasSize == CGSize(width: 378, height: 378), "original canvas preserved")
        check(PetEnhancements(values: defaults.values) == defaults, "preferences round trip")
        check(PetEnhancements(values: ["opacity": -10]).opacity == 0.25, "opacity lower bound")
        check(PetEnhancements(values: ["opacity": 5]).opacity == 1, "opacity upper bound")
        check(PetEnhancements(values: ["opacity": Double.nan]).opacity == 1, "invalid opacity fallback")
        check(PetEnhancements(values: ["performance": "invalid"]).performance == .balanced, "invalid performance fallback")
        for mode in PetPerformance.allCases {
            check(mode.frameInterval(active: false) > mode.frameInterval(active: true), "\(mode.rawValue) idle throttles")
            check(mode.frameInterval(active: true) >= 1 / 60, "\(mode.rawValue) max 60fps")
        }
        check(PetCadence.windowInterval(following: false, visible: true, economy: false) == 0.5, "desktop polling reduced to 2Hz")
        check(PetCadence.windowInterval(following: true, visible: false, economy: false) == 1, "hidden follow polling reduced")
        for kind in PetReaction.allCases {
            let session = PetReactionSession(kind: kind, startedAt: 100)
            check(kind.duration > 0 && kind.duration <= 15, "\(kind.rawValue) is time bounded")
            check(!kind.messages.isEmpty && !kind.symbol.isEmpty, "\(kind.rawValue) has local feedback")
            check(session.progress(at: 90) == 0, "\(kind.rawValue) clamps clock rewind")
            check(!session.finished(at: 100), "\(kind.rawValue) begins active")
            check(session.finished(at: 100 + kind.duration), "\(kind.rawValue) expires")
            check(session.progress(at: 1000) == 1, "\(kind.rawValue) progress bounded")
            check(session.pose(at: 101, reducedMotion: true) == PetReactionPose(), "\(kind.rawValue) respects reduced motion")
            check(session.pose(at: 1000) == PetReactionPose(), "\(kind.rawValue) leaves no residual transform")
            check(session.finished(at: .infinity), "\(kind.rawValue) invalid time expires safely")
        }
        let play = PetReactionSession(kind: .play, startedAt: 100)
        let left = play.pose(at: 101, pointerX: -1)
        let right = play.pose(at: 101, pointerX: 1)
        check(left.x < 0 && right.x > 0 && left.rotation < 0 && right.rotation > 0, "cursor reaction follows both directions")
        check(play.pose(at: 101, pointerX: 100).x == right.x, "cursor reaction bounded")
        check(play.pose(at: 101, pointerX: .nan, pointerY: .infinity) == PetReactionPose(), "invalid pointer stays neutral")
        check(PetRigMotion.sample(time: 100, idle: false) == PetRigPose(), "rig can stay completely still")
        check(PetRigMotion.sample(time: 100, reducedMotion: true) == PetRigPose(), "rig respects reduced motion")
        check(PetRigMotion.blink(at: 3.2) == 0, "blink actually closes the separate eyes")
        check(PetRigMotion.blink(at: 3.4) == 1, "blink reopens without residual deformation")
        check(PetRigMotion.blink(at: .infinity) == 1, "invalid blink time remains safe")
        check(PetRigMotion.blink(at: .greatestFiniteMagnitude).isFinite, "huge blink time cannot overflow")
        for mode in PetPerformance.allCases {
            check(PetRigMotion.frameInterval(performance: mode, moving: true) >= 1/30, "rig \(mode.rawValue) capped at 30 fps")
            check(PetRigMotion.frameInterval(performance: mode, moving: false) == 1, "rig \(mode.rawValue) still cadence")
        }
        for kind in PetReaction.allCases {
            let reaction = PetReactionSession(kind: kind, startedAt: 100)
            check(PetRigMotion.sample(time: 100, idle: false, reaction: reaction) == PetRigPose(), "\(kind.rawValue) rig enters continuously")
            check(PetRigMotion.sample(time: 100 + kind.duration, idle: false, reaction: reaction) == PetRigPose(), "\(kind.rawValue) rig returns to neutral")
            let posed = PetRigMotion.sample(time: 101, idle: false, reaction: reaction)
            check(posed.eyesOpen >= 0 && posed.eyesOpen <= 1 && posed.wingScale > 0, "\(kind.rawValue) rig geometry bounded")
        }
        let rigLeft = PetRigMotion.sample(time:101, idle:false, reaction:play, pointerX:-1)
        let rigRight = PetRigMotion.sample(time:101, idle:false, reaction:play, pointerX:1)
        check(rigLeft.headAngle < 0 && rigRight.headAngle > 0, "head tracks pointer independently")
        check(rigLeft.gazeX < 0 && rigRight.gazeX > 0, "eyes track pointer independently")
        let waving = PetRigMotion.sample(time:101, idle:false, reaction:PetReactionSession(kind:.wave, startedAt:100))
        check(waving.rightArm < -40 && waving.leftArm > 40, "wave articulates both arms without rotating the image")
        check(abs(waving.rightArm + waving.leftArm) > 1, "both arms wave with an offset rhythm, not a mirrored loop")
        for kind in [PetReaction.pet, .cuddle, .snack, .stretch] {
            let action = PetRigMotion.sample(time:101, idle:false, reaction:PetReactionSession(kind:kind, startedAt:100))
            check(action.leftArm > 0 && action.rightArm < 0, "\(kind.rawValue) moves both arms")
        }
        let suspended = PetRigMotion.sample(time:101, idle:false, dragging:true, dragAge:1, dragSway:1)
        check(suspended.leftLeg != suspended.rightLeg && suspended.leftArm > 0, "dragging has a separate suspended pose")
        check(PetRigMotion.sample(time:101, idle:false, releaseAge:1) == PetRigPose(), "landing animation is bounded")
        let nap = PetRigMotion.sample(time:101, idle:false, reaction:PetReactionSession(kind:.nap, startedAt:100), reducedMotion:true)
        check(nap.eyesOpen == 0 && nap.headAngle == 0, "reduced-motion nap changes expression without moving")
        var inertia = PetInertia(velocity: CGPoint(x: 9000, y: -9000))
        check(inertia.velocity == CGPoint(x: 800, y: -800), "release velocity bounded")
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 378, height: 490)
        var point = CGPoint(x: 500, y: 0)
        for _ in 0..<100 {
            point = inertia.step(origin: point, size: size, area: area, dt: 1 / 60)
            check(point.x >= 0 && point.x <= 622 && point.y >= 0 && point.y <= 310, "inertia stays on display")
        }
        check(inertia.finished, "inertia ends within bounded duration")
        let stopped = inertia.step(origin: point, size: size, area: area, dt: 1)
        check(stopped == point, "finished motion stays still")
        let invalid = PetInertia(velocity: CGPoint(x: Double.nan, y: Double.infinity))
        check(invalid.finished, "invalid velocity disabled")
        var negative = PetInertia(velocity: CGPoint(x: 300, y: 0))
        check(negative.step(origin: .zero, size: size, area: area, dt: -1) == .zero, "negative time ignored")
        print("\(count) checks passed")
    }
}
