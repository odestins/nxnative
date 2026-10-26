import Foundation

/// Shared HOME navigation with a deliberate first-repeat delay and analog hysteresis.
public struct ControllerNavigation: Sendable {
    public enum Direction: Sendable { case left, right, up, down }
    private var held: Direction?
    private var nextRepeat: TimeInterval = 0

    public init() {}
    public mutating func reset() { held = nil; nextRepeat = 0 }

    public mutating func update(x: Float, y: Float, now: TimeInterval) -> Direction? {
        guard x.isFinite, y.isFinite, now.isFinite else { reset(); return nil }
        let magnitude = max(abs(x), abs(y))
        guard magnitude >= (held == nil ? 0.55 : 0.35) else { reset(); return nil }

        let direction: Direction
        // Keep the current axis through small fluctuations near a diagonal or
        // activation threshold. Requiring a full release prevents accidental taps.
        if let held, component(held, x: x, y: y) >= 0.35,
           perpendicular(held, x: x, y: y) < component(held, x: x, y: y) + 0.12 {
            direction = held
        } else {
            guard magnitude >= 0.55 else { reset(); return nil }
            direction = abs(x) >= abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
        }
        if direction != held { held = direction; nextRepeat = now + 0.4; return direction }
        guard now >= nextRepeat else { return nil }
        nextRepeat = now + 0.14
        return direction
    }

    private func component(_ direction: Direction, x: Float, y: Float) -> Float {
        switch direction { case .left: -x; case .right: x; case .up: y; case .down: -y }
    }
    private func perpendicular(_ direction: Direction, x: Float, y: Float) -> Float {
        switch direction { case .left, .right: abs(y); case .up, .down: abs(x) }
    }
}
