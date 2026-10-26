import Foundation

/// A small, deterministic cutout rig. Parts have their own motion channels;
/// there is no video decoder, frame queue, or unbounded animation cache.
public struct PetRigPose: Equatable {
    public var bodyY = 0.0
    public var bodyAngle = 0.0
    public var bodyScaleY = 1.0
    public var headAngle = 0.0
    public var headY = 0.0
    public var hairAngle = 0.0
    public var fringeAngle = 0.0
    public var dressAngle = 0.0
    public var leftArm = 0.0
    public var rightArm = 0.0
    public var leftLeg = 0.0
    public var rightLeg = 0.0
    public var tailAngle = 0.0
    public var wingAngle = 0.0
    public var wingScale = 1.0
    public var eyesOpen = 1.0
    public var gazeX = 0.0
    public var gazeY = 0.0
    public var smile = 0.0
    public init() {}
}

public enum PetRigMotion {
    private static func finite(_ x: Double, limit: Double = 1) -> Double {
        x.isFinite ? max(-limit, min(limit, x)) : 0
    }
    private static func smooth(_ x: Double) -> Double {
        let v = max(0, min(1, x)); return v * v * (3 - 2 * v)
    }
    private static func envelope(_ age: Double, duration: Double, attack: Double = 0.35) -> Double {
        smooth(age / attack) * smooth((duration - age) / 0.55)
    }
    /// Short, slightly irregular blinks with a double blink every third cycle.
    public static func blink(at time: Double) -> Double {
        guard time.isFinite else { return 1 }
        let t = min(1e12, max(0, time))
        let cycle = Int(t / 6.7)
        let phase = t.truncatingRemainder(dividingBy: 6.7)
        func closure(_ start: Double) -> Double {
            let age = phase - start
            guard age >= 0, age < 0.25 else { return 0 }
            return age < 0.10 ? smooth(age / 0.10) : 1 - smooth((age - 0.10) / 0.15)
        }
        return 1 - max(closure(3.1), cycle % 3 == 1 ? closure(3.48) : 0)
    }
    public static func frameInterval(performance: PetPerformance, moving: Bool) -> Double {
        guard moving else { return 1 }
        // Atlas parts are smoothly transformed, not re-decoded on every tick.
        switch performance { case .economy: return 1 / 15; case .balanced: return 1 / 24; case .smooth: return 1 / 30 }
    }
    public static func sample(time: Double, idle: Bool = true, expressiveIdle: Bool = true,
                              reaction: PetReactionSession? = nil,
                              pointerX: Double = 0, pointerY: Double = 0,
                              dragging: Bool = false, dragAge: Double = 0,
                              dragSway: Double = 0, releaseAge: Double = 100,
                              reducedMotion: Bool = false) -> PetRigPose {
        var p = PetRigPose()
        let t = time.isFinite ? min(1e12, max(0, time)) : 0
        let active = reaction.flatMap { $0.finished(at: t) ? nil : $0 }
        if reducedMotion {
            p.eyesOpen = active?.kind == .nap ? 0 : 1
            p.smile = active?.kind == .cuddle || active?.kind == .snack ? 1 : 0
            return p
        }
        if idle {
            p.bodyScaleY = 1 + sin(t * 1.7) * 0.005
            p.headY = sin(t * 1.7 - 0.25) * 0.5
            p.headAngle = expressiveIdle ? sin(t * 0.63) * 1.3 : 0
            p.hairAngle = sin(t * 1.1 - 0.8) * 2
            p.fringeAngle = sin(t * 1.2 - 1.2) * 2.4
            p.dressAngle = sin(t * 1.1 - 1.4) * 0.8
            p.tailAngle = sin(t * 1.25 - 1) * 7
            p.wingAngle = sin(t * 1.6) * 3.4
            p.wingScale = 0.94 + sin(t * 1.6 - 0.25) * 0.04
            p.leftArm = sin(t * 1.1) * 1.7
            p.rightArm = sin(t * 1.1 - 0.8) * 1.7
            p.eyesOpen = blink(at: t)
            // One quiet, bounded gesture, then a long rest. Never repeats the
            // same gesture back-to-back or moves the desktop window by itself.
            if expressiveIdle {
                let age = t.truncatingRemainder(dividingBy: 13) - 8
                let reactionWeight = active.map { envelope($0.age(at:t), duration:$0.kind.duration) } ?? 0
                let dragWeight = dragging ? smooth(max(0, dragAge) / 0.18) : max(0, 1 - max(0, releaseAge) / 0.28)
                let weight = envelope(age, duration: 3.2) * (1 - max(reactionWeight, dragWeight))
                switch Int(t / 13) % 3 {
                case 0:
                    p.headAngle += sin(age * 1.6) * 6 * weight
                    p.gazeX = sin(age * 1.6) * weight
                case 1:
                    p.rightArm -= (48 + sin(age * 8) * 10) * weight
                    p.headAngle -= 4 * weight; p.smile = weight
                default:
                    p.headY += 2 * weight
                    p.eyesOpen *= 1 - 0.75 * weight
                    p.tailAngle += sin(age * 3) * 9 * weight
                    p.wingAngle += 6 * weight
                }
            }
        }
        if let session = active {
            let age = session.age(at: t)
            let f = envelope(age, duration: session.kind.duration)
            switch session.kind {
            case .pet:
                p.headAngle += sin(age * 4) * 6 * f
                p.headY += (1 + sin(age * 4)) * 1.2 * f
                p.leftArm += (11 + sin(age * 3.5) * 4) * f
                p.rightArm -= (17 + sin(age * 3.5 - 0.7) * 4) * f
                p.eyesOpen *= 1 - f * 0.95; p.smile = f
                p.tailAngle += sin(age * 5) * 15 * f
                p.wingAngle += sin(age * 4) * 6 * f
            case .cuddle:
                p.headAngle += 9 * f; p.headY += 1.5 * f
                p.leftArm += (28 + sin(age * 3) * 5) * f
                p.rightArm -= (22 + sin(age * 3 - 0.8) * 5) * f
                p.bodyAngle = -2.5 * f; p.smile = f
                p.eyesOpen *= 1 - 0.45 * f
                p.tailAngle += 14 * f
            case .snack:
                p.leftArm += (53 + sin(age * 5) * 4) * f
                p.rightArm -= (42 + sin(age * 5 - 0.8) * 4) * f
                p.headY += sin(age * 5) * f
                p.smile = (0.55 + sin(age * 8) * 0.45) * f
                p.eyesOpen *= 1 - 0.6 * f
                p.tailAngle += sin(age * 4) * 13 * f
            case .play:
                let x = finite(pointerX), y = finite(pointerY)
                p.headAngle += x * 10 * f; p.headY += y * 2 * f
                p.gazeX = x * f; p.gazeY = y * f
                p.bodyAngle = x * 1.5 * f
                p.leftArm += max(0, -x) * 25 * f
                p.rightArm -= max(0, x) * 25 * f
                p.tailAngle += -x * 12 * f
            case .nap:
                p.eyesOpen *= 1 - f
                p.headAngle += 10 * f; p.headY += 3 * f
                p.bodyY += 2 * f; p.wingScale -= 0.14 * f
                p.leftArm -= 3 * f; p.rightArm += 3 * f
            case .wave:
                p.leftArm += (64 + sin(age * 9 - 1.2) * 12) * f
                p.rightArm -= (67 + sin(age * 9) * 12) * f
                p.headAngle -= 5 * f; p.smile = f
                p.tailAngle += sin(age * 4) * 13 * f
                p.wingAngle += 5 * f
            case .stretch:
                p.leftArm += (47 + sin(age * 2) * 3) * f
                p.rightArm -= (49 + sin(age * 2 - 0.6) * 3) * f
                p.headY -= 2 * f; p.headAngle -= 3 * f
                p.bodyScaleY += 0.02 * f
                p.wingAngle += 11 * f; p.wingScale += 0.08 * f
                p.eyesOpen *= 1 - f; p.smile = f
            }
            p.hairAngle += sin(age * 2.6 - 0.5) * 2.5 * f
            p.fringeAngle += sin(age * 3 - 1) * 3 * f
            p.dressAngle += sin(age * 2.6 - 1.2) * 0.8 * f
        }
        // A picked-up pose with trailing limbs, followed by a short, decaying
        // landing response. These channels are separate from window inertia.
        let release = releaseAge.isFinite ? max(0, releaseAge) : 100
        let suspension = dragging ? smooth(max(0, dragAge) / 0.18) : max(0, 1 - release / 0.28)
        if suspension > 0 {
            let sway = finite(dragSway)
            p.bodyAngle += sway * 7 * suspension
            p.headAngle -= (sway * 5 + 4) * suspension
            p.headY -= 2 * suspension
            p.leftArm += (23 + sin(t * 5) * 6) * suspension
            p.rightArm -= (23 + sin(t * 5 + 1) * 6) * suspension
            p.leftLeg += 9 * suspension; p.rightLeg -= 12 * suspension
            p.hairAngle -= sway * 9 * suspension
            p.fringeAngle -= sway * 6 * suspension
            p.dressAngle -= sway * 2 * suspension
            p.wingAngle += 14 * suspension
            p.tailAngle += (sway * 14 + sin(t * 5) * 8) * suspension
            p.eyesOpen = 1; p.smile = 0.5 * suspension
        }
        if !dragging && release < 0.7 {
            let bounce = sin(release / 0.7 * .pi * 2) * exp(-release * 6)
            p.bodyScaleY -= bounce * 0.06
            p.headY += bounce * 2; p.hairAngle += bounce * 4
            p.wingAngle += bounce * 7
        }
        p.eyesOpen = max(0, min(1, p.eyesOpen))
        return p
    }
}
