import Foundation
import CoreGraphics

public enum PetPerformance: String, CaseIterable, Codable {
    case economy, balanced, smooth
    public var title: String {
        switch self { case .economy: return "省电"; case .balanced: return "平衡"; case .smooth: return "流畅" }
    }
    public func frameInterval(active: Bool) -> Double {
        switch self {
        case .economy: return active ? 1 / 15 : 1 / 4
        case .balanced: return active ? 1 / 30 : 1 / 8
        case .smooth: return active ? 1 / 60 : 1 / 15
        }
    }
}

public enum PetFullBodyStyle: String, CaseIterable, Codable {
    case winged, chibi
    public var title: String {
        switch self { case .winged: return "龙翼长裙 · 参考图版"; case .chibi: return "Q 版全身" }
    }
    public var assetName: String {
        switch self { case .winged: return "gpt-dragon-niang-winged-v2.png"; case .chibi: return "gpt-dragon-niang-fullbody.png" }
    }
}

/// Independent, versioned preferences. Missing/malformed fields keep safe defaults.
public struct PetEnhancements: Equatable, Codable {
    public var fullBody = true
    public var fullBodyStyle = PetFullBodyStyle.winged
    public var idleMotion = true
    public var articulatedMotion = true
    public var inertia = true
    public var edgePeek = true
    public var positionLocked = false
    public var clickThrough = false
    public var opacity = 1.0
    public var performance = PetPerformance.balanced
    public init() {}
    public init(values: [String: Any]) {
        fullBody = values["fullBody"] as? Bool ?? true
        fullBodyStyle = PetFullBodyStyle(rawValue: values["fullBodyStyle"] as? String ?? "winged") ?? .winged
        idleMotion = values["idleMotion"] as? Bool ?? true
        articulatedMotion = values["articulatedMotion"] as? Bool ?? true
        inertia = values["inertia"] as? Bool ?? true
        edgePeek = values["edgePeek"] as? Bool ?? true
        positionLocked = values["positionLocked"] as? Bool ?? false
        clickThrough = values["clickThrough"] as? Bool ?? false
        let alpha = (values["opacity"] as? NSNumber)?.doubleValue ?? 1
        opacity = alpha.isFinite ? min(1, max(0.25, alpha)) : 1
        performance = PetPerformance(rawValue: values["performance"] as? String ?? "balanced") ?? .balanced
    }
    public var values: [String: Any] {
        ["fullBody": fullBody, "fullBodyStyle": fullBodyStyle.rawValue, "idleMotion": idleMotion, "articulatedMotion": articulatedMotion, "inertia": inertia,
         "edgePeek": edgePeek, "positionLocked": positionLocked, "clickThrough": clickThrough,
         "opacity": opacity, "performance": performance.rawValue]
    }
    public var canvasSize: CGSize { CGSize(width: 378, height: fullBody ? 490 : 378) }
}

/// Short, bounded release motion. Never creates a permanent 60 Hz background loop.
public struct PetInertia {
    public private(set) var velocity: CGPoint
    public private(set) var elapsed: Double = 0
    public init(velocity: CGPoint) {
        func limited(_ value: Double) -> Double { value.isFinite ? min(800, max(-800, value)) : 0 }
        self.velocity = CGPoint(x: limited(velocity.x), y: limited(velocity.y))
    }
    public var finished: Bool { elapsed >= 0.8 || hypot(velocity.x, velocity.y) < 8 }
    public mutating func step(origin: CGPoint, size: CGSize, area: CGRect, dt: Double) -> CGPoint {
        guard dt.isFinite, dt > 0, !finished else { return origin }
        let delta = min(dt, 1 / 15)
        elapsed += delta
        let proposed = CGPoint(x: origin.x + velocity.x * delta, y: origin.y + velocity.y * delta)
        let fitted = WidgetPlacement.desktopFrame(area: area, size: size, origin: proposed).origin
        if abs(fitted.x - proposed.x) > 0.01 { velocity.x *= -0.22 }
        if abs(fitted.y - proposed.y) > 0.01 { velocity.y *= -0.22 }
        let damping = exp(-7.5 * delta)
        velocity.x *= damping; velocity.y *= damping
        return fitted
    }
}

public enum PetCadence {
    public static func windowInterval(following: Bool, visible: Bool, economy: Bool) -> Double {
        guard visible else { return 1 }
        return following ? (economy ? 1 / 15 : 1 / 30) : 0.5
    }
}
