// hidprobe.swift — mostra o que cada botão do mouse realmente envia ao macOS.
//
// Como rodar (Terminal):
//   1. xcode-select --install        (só se ainda não tiver as ferramentas)
//   2. swift hidprobe.swift
//   3. Se pedir, libere o Terminal em Ajustes do Sistema > Privacidade e Segurança >
//      Monitoramento de Entrada (e Acessibilidade), feche e rode de novo.
//   4. Aperte cada botão lateral 2 ou 3 vezes, devagar. Ctrl+C para sair.
//
// Duas camadas são registradas:
//   [HID]   o relatório cru que o mouse manda (página/uso HID)
//   [EVENT] o evento que o macOS gera a partir dele (o que apps como o Mac Mouse Fix enxergam)

import AppKit
import Foundation
import IOKit.hid

setvbuf(stdout, nil, _IONBF, 0)

func prop(_ d: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(d, key as CFString)
}

func deviceName(_ d: IOHIDDevice) -> String {
    prop(d, kIOHIDProductKey) as? String ?? "(sem nome)"
}

func label(page: UInt32, usage: UInt32) -> String {
    switch (page, usage) {
    case (0x09, _): return "Botão do mouse \(usage)"
    case (0x0C, 0x224): return "Consumer: AC Back (voltar)"
    case (0x0C, 0x225): return "Consumer: AC Forward (avançar)"
    case (0x0C, 0x29F): return "Consumer: Mission Control"
    case (0x0C, _): return "Consumer (mídia/sistema)"
    case (0x07, 0xE0...0xE7): return "Teclado: modificador"
    case (0x07, _): return "Teclado: tecla"
    case (0x01, _): return "Generic Desktop"
    case (0xFF00...0xFFFF, _): return "Página do fabricante"
    default: return ""
    }
}

// MARK: - Camada HID (relatórios crus)

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, nil)

IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let vid = prop(device, kIOHIDVendorIDKey) as? Int ?? 0
    let pid = prop(device, kIOHIDProductIDKey) as? Int ?? 0
    let transport = prop(device, kIOHIDTransportKey) as? String ?? "?"
    let page = prop(device, kIOHIDPrimaryUsagePageKey) as? Int ?? 0
    let usage = prop(device, kIOHIDPrimaryUsageKey) as? Int ?? 0
    print(String(format: "[HID] dispositivo: %@  vid=0x%04X pid=0x%04X  %@  uso primário=0x%02X/0x%02X",
                 deviceName(device), vid, pid, transport, page, usage))
}, nil)

IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let v = IOHIDValueGetIntegerValue(value)

    // Ignora movimento e roda, que inundam a saída.
    if page == 0x01 && [0x30, 0x31, 0x38].contains(usage) { return }
    if page == 0x0C && usage == 0x238 { return } // AC Pan (roda horizontal)
    // Ignora os campos de array do teclado que não são teclas.
    if page == 0x07 && (usage < 4 || usage > 0xFFFF) { return }

    let name = deviceName(IOHIDElementGetDevice(element))
    print(String(format: "[HID]   %@: página=0x%04X uso=0x%04X valor=%ld  %@",
                 name, page, usage, v, label(page: page, usage: usage)))
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("[HID] Sem acesso aos dispositivos (código \(openResult)). Libere o Terminal em Monitoramento de Entrada e rode de novo.")
}

// MARK: - Camada de eventos do macOS

func describe(_ type: CGEventType, _ event: CGEvent) -> String? {
    switch type.rawValue {
    case 5, 6, 7, 22, 27: // movimento, arrasto, rolagem
        return nil
    case 1, 2, 3, 4, 25, 26:
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let kind = [1: "esquerdo↓", 2: "esquerdo↑", 3: "direito↓", 4: "direito↑", 25: "outro↓", 26: "outro↑"][Int(type.rawValue)]!
        return "botão do mouse \(kind)  número=\(button)  (0=esq, 1=dir, 2=meio, 3=voltar, 4=avançar)"
    case 10, 11:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var mods = ""
        if flags.contains(.maskCommand) { mods += "⌘" }
        if flags.contains(.maskControl) { mods += "⌃" }
        if flags.contains(.maskAlternate) { mods += "⌥" }
        if flags.contains(.maskShift) { mods += "⇧" }
        let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
        return "tecla \(type.rawValue == 10 ? "↓" : "↑")  keycode=\(code)  \(mods)\(chars)"
    case 12:
        return "modificadores mudaram: 0x\(String(event.flags.rawValue, radix: 16))"
    case 14:
        guard let ns = NSEvent(cgEvent: event) else { return "evento de sistema" }
        let key = (ns.data1 & 0xFFFF_0000) >> 16
        let down = ((ns.data1 & 0xFF00) >> 8) == 0x0A
        return "evento de sistema (tecla especial)  subtipo=\(ns.subtype.rawValue)  código=\(key)  \(down ? "↓" : "↑")"
    default:
        if let ns = NSEvent(cgEvent: event) {
            var s = "tipo=\(type.rawValue) NSEvent=\(ns.type.rawValue)"
            if ns.type == .swipe { s += "  GESTO DE SWIPE deltaX=\(ns.deltaX) deltaY=\(ns.deltaY)" }
            return s
        }
        return "tipo=\(type.rawValue)"
    }
}

var tap: CFMachPort?
tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask.max,
    callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        } else if let text = describe(type, event) {
            print("[EVENT] \(text)")
        }
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil)

if let tap {
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
} else {
    print("[EVENT] Não consegui escutar eventos. Libere o Terminal em Acessibilidade e Monitoramento de Entrada e rode de novo.")
}

print("Pronto. Aperte cada botão lateral algumas vezes, sem mexer no trackpad. Ctrl+C para sair.\n")
CFRunLoopRun()
