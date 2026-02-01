import Foundation
import AppKit
import Carbon

/// 全局快捷键管理器 - 支持按住说话模式
class HotkeyManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentHotkey: HotkeyCombo = HotkeyCombo.fnKey
    @Published var isListeningForHotkey: Bool = false
    @Published var isKeyHeld: Bool = false
    
    // MARK: - Private Properties
    
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    
    // MARK: - Singleton
    
    static let shared = HotkeyManager()
    
    private init() {
        loadHotkey()
    }
    
    deinit {
        stopListening()
    }
    
    // MARK: - Public Methods
    
    /// 设置按下快捷键回调
    func setKeyDownCallback(_ callback: @escaping () -> Void) {
        self.onKeyDown = callback
    }
    
    /// 设置松开快捷键回调
    func setKeyUpCallback(_ callback: @escaping () -> Void) {
        self.onKeyUp = callback
    }
    
    /// 开始监听全局快捷键（按住模式）
    func startListening() {
        stopListening()
        
        // 如果使用Fn键，监听修饰键变化
        if currentHotkey.isFnKey {
            startFnKeyListening()
        } else {
            startRegularKeyListening()
        }
    }
    
    private func startFnKeyListening() {
        // 监听Fn键需要使用flagsChanged事件
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFnKey(event)
        }
        
        // 本地监听
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFnKey(event)
            return event
        }
    }
    
    private func startRegularKeyListening() {
        // 全局监听键盘按下
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // 本地监听
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }
    
    private func handleFnKey(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)
        
        if fnPressed && !isKeyHeld && !isListeningForHotkey {
            isKeyHeld = true
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?()
            }
        } else if !fnPressed && isKeyHeld {
            isKeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
        }
    }
    
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !isListeningForHotkey else { return false }
        
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        
        if event.keyCode == currentHotkey.keyCode && modifiers == currentHotkey.modifiers {
            if event.type == .keyDown && !isKeyHeld {
                isKeyHeld = true
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyDown?()
                }
                return true
            } else if event.type == .keyUp && isKeyHeld {
                isKeyHeld = false
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyUp?()
                }
                return true
            }
        }
        return false
    }
    
    /// 停止监听
    func stopListening() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        isKeyHeld = false
    }
    
    /// 开始录制新快捷键
    func startRecordingHotkey() {
        isListeningForHotkey = true
        stopListening()
    }
    
    /// 停止录制快捷键
    func stopRecordingHotkey() {
        isListeningForHotkey = false
        startListening()
    }
    
    /// 记录新快捷键
    func recordHotkey(from event: NSEvent) -> Bool {
        guard isListeningForHotkey else { return false }
        
        // 检查是否是Fn键
        if event.modifierFlags.contains(.function) && event.keyCode == 0x3F {
            currentHotkey = HotkeyCombo.fnKey
            saveHotkey()
            isListeningForHotkey = false
            startListening()
            return true
        }
        
        // 忽略单独的修饰键
        let modifierKeyCodes: [UInt16] = [0x38, 0x3B, 0x3A, 0x37, 0x36, 0x3C, 0x3D, 0x3E]
        if modifierKeyCodes.contains(event.keyCode) {
            return false
        }
        
        let newHotkey = HotkeyCombo(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection([.command, .option, .control, .shift])
        )
        
        currentHotkey = newHotkey
        saveHotkey()
        isListeningForHotkey = false
        startListening()
        
        return true
    }
    
    /// 设置为Fn键
    func setFnKey() {
        currentHotkey = HotkeyCombo.fnKey
        saveHotkey()
        startListening()
    }
    
    /// 重置为默认快捷键
    func resetToDefault() {
        currentHotkey = HotkeyCombo.default
        saveHotkey()
        startListening()
    }
    
    // MARK: - Private Methods
    
    private func saveHotkey() {
        UserDefaults.standard.set(Int(currentHotkey.keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(currentHotkey.modifiers.rawValue), forKey: "hotkeyModifiers")
        UserDefaults.standard.set(currentHotkey.isFnKey, forKey: "hotkeyIsFnKey")
    }
    
    private func loadHotkey() {
        if let isFnKey = UserDefaults.standard.object(forKey: "hotkeyIsFnKey") as? Bool, isFnKey {
            currentHotkey = HotkeyCombo.fnKey
        } else if let keyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int,
                  let modifiersRaw = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int {
            currentHotkey = HotkeyCombo(
                keyCode: UInt16(keyCode),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiersRaw))
            )
        }
    }
}

// MARK: - Hotkey Combo

struct HotkeyCombo: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let isFnKey: Bool
    
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isFnKey: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isFnKey = isFnKey
    }
    
    // 默认使用 fn 键
    static let `default` = HotkeyCombo(
        keyCode: 0x3F,
        modifiers: [],
        isFnKey: true
    )
    
    static let fnKey = HotkeyCombo(
        keyCode: 0x3F,
        modifiers: [],
        isFnKey: true
    )
    
    // 备用: Option+Space
    static let optionSpace = HotkeyCombo(
        keyCode: 49, // Space
        modifiers: [.option],
        isFnKey: false
    )
    
    var displayString: String {
        if isFnKey {
            return "fn"
        }
        
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        parts.append(keyCodeToString(keyCode))
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            50: "`", 51: "⌫", 53: "⎋", 63: "fn",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
            113: "F15", 118: "F4", 119: "F2", 120: "F1", 122: "F3",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }
}
