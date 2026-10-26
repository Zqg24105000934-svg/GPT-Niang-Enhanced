import Foundation

/// Local, time-bounded play states; no account access or network requests.
public enum PetReaction: String, CaseIterable {
    case pet, cuddle, snack, play, nap, wave, stretch

    public var title: String {
        switch self {
        case .pet: return "摸摸头"
        case .cuddle: return "撒个娇"
        case .snack: return "喂小点心"
        case .play: return "逗逗她 · 12 秒"
        case .nap: return "小憩 · 15 秒"
        case .wave: return "双手挥挥"
        case .stretch: return "伸个懒腰"
        }
    }
    public var duration: Double {
        switch self { case .pet, .cuddle, .wave: return 4.5; case .snack, .stretch: return 5; case .play: return 12; case .nap: return 15 }
    }
    public var symbol: String {
        switch self { case .pet, .cuddle: return "heart.fill"; case .snack: return "birthday.cake.fill"; case .play: return "sparkles"; case .nap: return "moon.zzz.fill"; case .wave: return "hand.wave.fill"; case .stretch: return "sun.max.fill" }
    }
    public var mood: String {
        switch self { case .pet: return "开心"; case .cuddle: return "害羞"; case .snack: return "满足"; case .play: return "好奇"; case .nap: return "小憩中 · 点击唤醒"; case .wave: return "在这里呀"; case .stretch: return "舒展一下" }
    }
    public var messages: [String] {
        switch self {
        case .pet: return ["唔……再摸一下就好。", "今天也有被温柔对待呢。", "摸摸头，烦恼飞走啦。"]
        case .cuddle: return ["被你发现我在等你啦。", "再陪我一小会儿，好不好？", "收到！给你一颗小小的心。"]
        case .snack: return ["啊呜……甜度刚刚好！", "给你留了一半小点心。", "点心能量补充完毕！"]
        case .play: return ["左右移动鼠标，\n我会跟着小星星看。"]
        case .nap: return ["让我眯一会儿……\n点一下就会醒。"]
        case .wave: return ["嘿，我在这里呀！", "忙完记得看看我。"]
        case .stretch: return ["呼——伸个懒腰，\n你也活动一下吧。"]
        }
    }
}

public struct PetReactionSession: Equatable {
    public let kind: PetReaction
    public let startedAt: TimeInterval
    public init(kind: PetReaction, startedAt: TimeInterval) {
        self.kind = kind; self.startedAt = startedAt.isFinite ? startedAt : 0
    }
    public func age(at time: TimeInterval) -> Double { time.isFinite ? max(0, time - startedAt) : kind.duration }
    public func finished(at time: TimeInterval) -> Bool { age(at: time) >= kind.duration }
    public func progress(at time: TimeInterval) -> Double { min(1, age(at: time) / kind.duration) }
    public func pose(at time: TimeInterval, pointerX: Double = 0, pointerY: Double = 0, reducedMotion: Bool = false) -> PetReactionPose {
        guard !reducedMotion, !finished(at: time) else { return PetReactionPose() }
        let t = age(at: time)
        let fade = min(1, t / 0.2) * min(1, (kind.duration - t) / 0.4)
        var pose = PetReactionPose()
        switch kind {
        case .pet:
            pose.rotation = sin(t * 4.5) * 2.5 * fade
            pose.scaleY = 1 - (sin(t * 4.5) + 1) * 0.008 * fade
        case .cuddle:
            pose.rotation = sin(t * 5) * 4 * fade
            pose.y = -abs(sin(t * 3.5)) * 5 * fade
        case .snack:
            pose.y = -abs(sin(t * 5)) * 3 * fade
            pose.scaleX = 1 + sin(t * 7) * 0.009 * fade
        case .play:
            let x = pointerX.isFinite ? min(1, max(-1, pointerX)) : 0
            let y = pointerY.isFinite ? min(1, max(-1, pointerY)) : 0
            pose.rotation = x * 6 * fade
            pose.x = x * 6 * fade; pose.y = y * 3 * fade
        case .nap:
            pose.rotation = -5 * fade
            pose.scaleY = 1 - 0.025 * fade + sin(t * 1.4) * 0.004 * fade
        case .wave:
            pose.rotation = sin(t * 6) * 3 * fade
        case .stretch:
            pose.scaleY = 1 + 0.02 * fade
        }
        return pose
    }
}

public struct PetReactionPose: Equatable {
    public var x = 0.0
    public var y = 0.0
    public var rotation = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    public init() {}
}
