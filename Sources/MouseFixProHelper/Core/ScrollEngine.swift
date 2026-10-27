import MouseFixShared
import CoreGraphics
import Foundation

/// Rolagem suave, direção e velocidade, só para rodinhas de mouse (trackpad e Magic Mouse passam intactos).
/// O timer de animação só existe enquanto há rolagem acontecendo: parado, o custo é zero.
final class ScrollEngine {
    var settings = ScrollSettings()

    private var remainingY = 0.0
    private var remainingX = 0.0
    private var carryY = 0.0
    private var carryX = 0.0
    private var lastTick: TimeInterval = 0
    private var streak = 1.0
    private var timer: DispatchSourceTimer?

    /// Pixels por "clique" da rodinha na velocidade 1.
    private let pixelsPerLine = 40.0
    /// Fração do restante aplicada por quadro (curva de desaceleração).
    private let easing = 0.22

    func handle(_ event: CGEvent) -> CGEvent? {
        // Trackpad e Magic Mouse já mandam rolagem contínua e suave.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return event }

        let sign = settings.reverse ? -1.0 : 1.0
        guard settings.smooth else {
            if sign == 1 && settings.speed == 1 { return event }
            scale(event, by: sign * settings.speed)
            return event
        }

        let lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        if lineY == 0 && lineX == 0 { return event }

        // Girar rápido acelera, como no trackpad.
        let now = ProcessInfo.processInfo.systemUptime
        streak = now - lastTick < 0.08 ? min(streak + 0.4, 5) : 1
        lastTick = now

        // Mudou de direção: descarta o que sobrou na direção antiga.
        if lineY != 0 && (remainingY * lineY * sign) < 0 { remainingY = 0 }
        if lineX != 0 && (remainingX * lineX * sign) < 0 { remainingX = 0 }

        let step = pixelsPerLine * settings.speed * streak * sign
        remainingY += lineY * step
        remainingX += lineX * step
        startTimer()
        return nil
    }

    private func scale(_ e: CGEvent, by factor: Double) {
        for (line, point, fixed) in [
            (CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis1),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2),
        ] {
            let l = Double(e.getIntegerValueField(line))
            if l != 0 {
                let scaled = l * factor
                e.setIntegerValueField(line, value: Int64(scaled.rounded(.awayFromZero)))
            }
            e.setIntegerValueField(point, value: Int64((Double(e.getIntegerValueField(point)) * factor).rounded()))
            e.setDoubleValueField(fixed, value: e.getDoubleValueField(fixed) * factor)
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.frame() }
        timer = t
        t.resume()
    }

    private func frame() {
        func take(_ remaining: inout Double, _ carry: inout Double) -> Int32 {
            var d = remaining * easing
            if abs(remaining) < 2 { d = remaining }
            remaining -= d
            carry += d
            let whole = carry.rounded(.towardZero)
            carry -= whole
            return Int32(whole)
        }
        let dy = take(&remainingY, &carryY)
        let dx = take(&remainingX, &carryX)
        if dy != 0 || dx != 0,
           let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
            e.setIntegerValueField(.eventSourceUserData, value: ActionRunner.marker)
            e.post(tap: .cghidEventTap)
        }
        if abs(remainingY) < 0.5 && abs(remainingX) < 0.5 {
            remainingY = 0
            remainingX = 0
            carryY = 0
            carryX = 0
            timer?.cancel()
            timer = nil
        }
    }
}
