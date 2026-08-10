import Carbon
import Foundation

struct HotKeySpec: Equatable {
  let keyCode: UInt32
  let modifiers: UInt32

  init?(_ text: String) {
    let pieces = text.lowercased().split(separator: "+").map(String.init)
    guard let key = pieces.last, let keyCode = Self.keyCodes[key] else { return nil }

    var modifiers: UInt32 = 0
    for modifier in pieces.dropLast() {
      switch modifier {
      case "ctrl", "control": modifiers |= UInt32(controlKey)
      case "cmd", "command": modifiers |= UInt32(cmdKey)
      case "opt", "option", "alt": modifiers |= UInt32(optionKey)
      case "shift": modifiers |= UInt32(shiftKey)
      default: return nil
      }
    }

    guard modifiers != 0 else { return nil }
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  private static let keyCodes: [String: UInt32] = [
    "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
    "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
    "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
    "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
    "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
    "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
    "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
    "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
    "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
    "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
    "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
    "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
    "9": UInt32(kVK_ANSI_9), "space": UInt32(kVK_Space),
  ]
}

final class GlobalHotKey {
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private var callback: (() -> Void)?

  @discardableResult
  func register(_ text: String, callback: @escaping () -> Void) -> Bool {
    unregister()
    guard let spec = HotKeySpec(text) else { return false }
    self.callback = callback

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return noErr }
        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
        hotKey.callback?()
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    guard status == noErr else {
      unregister()
      return false
    }

    let identifier = EventHotKeyID(signature: Self.signature, id: 1)
    let registration = RegisterEventHotKey(
      spec.keyCode,
      spec.modifiers,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    if registration != noErr {
      unregister()
      return false
    }
    return true
  }

  func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
    hotKeyRef = nil
    eventHandler = nil
    callback = nil
  }

  deinit {
    unregister()
  }

  private static let signature: OSType = 0x5072_6D70  // "Prmp"
}
