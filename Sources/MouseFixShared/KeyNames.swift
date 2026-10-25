import CoreGraphics

/// Tradução entre usos HID de teclado e keycodes do macOS.
/// Os dois descrevem a posição física da tecla, então a tabela vale para qualquer layout (ABNT2 incluso).
public enum KeyNames {
    private static let table: [UInt32: (CGKeyCode, String)] = [
        0x04: (0, "A"), 0x05: (11, "B"), 0x06: (8, "C"), 0x07: (2, "D"), 0x08: (14, "E"),
        0x09: (3, "F"), 0x0A: (5, "G"), 0x0B: (4, "H"), 0x0C: (34, "I"), 0x0D: (38, "J"),
        0x0E: (40, "K"), 0x0F: (37, "L"), 0x10: (46, "M"), 0x11: (45, "N"), 0x12: (31, "O"),
        0x13: (35, "P"), 0x14: (12, "Q"), 0x15: (15, "R"), 0x16: (1, "S"), 0x17: (17, "T"),
        0x18: (32, "U"), 0x19: (9, "V"), 0x1A: (13, "W"), 0x1B: (7, "X"), 0x1C: (16, "Y"),
        0x1D: (6, "Z"),
        0x1E: (18, "1"), 0x1F: (19, "2"), 0x20: (20, "3"), 0x21: (21, "4"), 0x22: (23, "5"),
        0x23: (22, "6"), 0x24: (26, "7"), 0x25: (28, "8"), 0x26: (25, "9"), 0x27: (29, "0"),
        0x28: (36, "↩"), 0x29: (53, "esc"), 0x2A: (51, "⌫"), 0x2B: (48, "⇥"), 0x2C: (49, L("espaço", "space")),
        0x2D: (27, "-"), 0x2E: (24, "="), 0x2F: (33, "["), 0x30: (30, "]"), 0x31: (42, "\\"),
        0x33: (41, ";"), 0x34: (39, "'"), 0x35: (50, "`"), 0x36: (43, ","), 0x37: (47, "."),
        0x38: (44, "/"),
        0x3A: (122, "F1"), 0x3B: (120, "F2"), 0x3C: (99, "F3"), 0x3D: (118, "F4"),
        0x3E: (96, "F5"), 0x3F: (97, "F6"), 0x40: (98, "F7"), 0x41: (100, "F8"),
        0x42: (101, "F9"), 0x43: (109, "F10"), 0x44: (103, "F11"), 0x45: (111, "F12"),
        0x4A: (115, "Home"), 0x4B: (116, "Page Up"), 0x4C: (117, "⌦"), 0x4D: (119, "End"),
        0x4E: (121, "Page Down"), 0x4F: (124, "→"), 0x50: (123, "←"), 0x51: (125, "↓"), 0x52: (126, "↑"),
    ]

    public static func keyCode(forUsage usage: UInt32) -> CGKeyCode? { table[usage]?.0 }

    public static func name(forUsage usage: UInt32) -> String {
        table[usage]?.1 ?? "tecla 0x\(String(usage, radix: 16))"
    }

    /// Bit de modificador do CGEvent para os usos 0xE0...0xE7.
    public static func modifierFlag(forUsage usage: UInt32) -> CGEventFlags? {
        switch usage {
        case 0xE0, 0xE4: return .maskControl
        case 0xE1, 0xE5: return .maskShift
        case 0xE2, 0xE6: return .maskAlternate
        case 0xE3, 0xE7: return .maskCommand
        default: return nil
        }
    }

    public static func symbols(for flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s
    }
}
