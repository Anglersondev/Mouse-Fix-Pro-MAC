import MouseFixShared

/// Correlaciona o tipo, código, fase e horário dos eventos Quartz com o relatório recebido do mouse.
struct HIDCorrelation {
    enum Signal: Equatable {
        case key(Int64)
        case media(Int)
        case swipe
    }

    private struct Match {
        let signal: Signal
        let pressed: Bool
        let time: UInt64
    }

    private static let tolerance: UInt64 = 12_000_000 // 12 ms, em nanossegundos
    private var pending: [Match] = []

    mutating func record(_ trigger: Trigger, pressed: Bool, time: UInt64) {
        let signal: Signal
        switch trigger {
        case .hid(Trigger.keyboardPage, let usage):
            guard let code = KeyNames.keyCode(forUsage: usage) else { return }
            signal = .key(Int64(code))
        case .hid(Trigger.consumerPage, 0x224), .hid(Trigger.consumerPage, 0x225):
            guard pressed else { return }
            signal = .swipe
        case .hid(Trigger.consumerPage, let usage):
            guard let code = Self.mediaCodes[usage] else { return }
            signal = .media(code)
        default:
            return
        }

        pending.removeAll { time > $0.time && time - $0.time > Self.tolerance }
        if pending.count == 32 { pending.removeFirst() }
        pending.append(Match(signal: signal, pressed: pressed, time: time))
    }

    mutating func consume(_ signal: Signal, pressed: Bool, time: UInt64) -> Bool {
        guard let i = pending.firstIndex(where: {
            let delta = max(time, $0.time) - min(time, $0.time)
            return $0.signal == signal && $0.pressed == pressed && delta <= Self.tolerance
        }) else { return false }
        pending.remove(at: i)
        return true
    }

    // Usos HID Consumer → NX_KEYTYPE_* para teclas de mídia conhecidas pelo macOS.
    private static let mediaCodes: [UInt32: Int] = [
        0x6F: 2, 0x70: 3, // brilho
        0xB0: 16, 0xB3: 19, 0xB4: 20, 0xB5: 17, 0xB6: 18, 0xCD: 16,
        0xE2: 7, 0xE9: 0, 0xEA: 1,
    ]
}
