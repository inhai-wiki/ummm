import SwiftUI
import AppKit
import AVFoundation
import Speech

@main
struct UmmmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 空的Settings场景（必须有一个场景）
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let speechRecognizer = SpeechRecognizer()
    let hotkeyManager = HotkeyManager.shared
    var floatingWindow: FloatingIndicatorWindow?
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动时请求所有权限
        // 只检查辅助功能权限（必需的），其他权限在使用时按需请求
        checkAccessibilityPermission()
        
        // 设置菜单栏图标
        setupStatusItem()
        
        // 设置全局快捷键回调（按住模式）
        hotkeyManager.setKeyDownCallback { [weak self] in
            self?.startRecording()
        }
        
        hotkeyManager.setKeyUpCallback { [weak self] in
            self?.stopRecording()
        }
        
        hotkeyManager.startListening()
        
        // 隐藏Dock图标
        NSApp.setActivationPolicy(.accessory)
    }
    
    // MARK: - 权限请求
    
    private func requestAllPermissions() {
        // 1. 请求麦克风权限
        requestMicrophonePermission()
        
        // 2. 请求语音识别权限（同时更新 SpeechRecognizer 状态）
        speechRecognizer.requestAuthorization()
        
        // 3. 检查辅助功能权限
        checkAccessibilityPermission()
    }
    
    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.showPermissionAlert(
                            title: "Microphone Access Required",
                            message: "Ummm needs microphone access to convert your voice to text. Please enable it in System Settings > Privacy & Security > Microphone.",
                            settingsKey: "Privacy_Microphone"
                        )
                    }
                }
            }
        case .denied, .restricted:
            showPermissionAlert(
                title: "Microphone Access Required",
                message: "Ummm needs microphone access to convert your voice to text. Please enable it in System Settings > Privacy & Security > Microphone.",
                settingsKey: "Privacy_Microphone"
            )
        case .authorized:
            break
        @unknown default:
            break
        }
    }
    
    private func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                DispatchQueue.main.async {
                    self.showPermissionAlert(
                        title: "Speech Recognition Access Required",
                        message: "Ummm needs speech recognition access for local voice-to-text conversion. Please enable it in System Settings > Privacy & Security > Speech Recognition.",
                        settingsKey: "Privacy_SpeechRecognition"
                    )
                }
            }
        }
    }
    
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            // 系统会自动弹出提示，不需要额外处理
        }
    }
    
    private func showPermissionAlert(title: String, message: String, settingsKey: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // 打开系统设置
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsKey)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - 设置菜单栏图标
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ummm")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        
        // 创建Popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 260, height: 220)
        popover?.behavior = .transient
        popover?.animates = true
        
        let menuView = MenuBarView(onToggleRecording: { [weak self] in
            self?.toggleRecording()
            self?.popover?.close()
        })
            .environmentObject(speechRecognizer)
            .environmentObject(hotkeyManager)
        
        popover?.contentViewController = NSHostingController(rootView: menuView)
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // 右键：显示菜单
            showPopover()
        } else {
            // 左键：开始/停止录音
            toggleRecording()
        }
    }
    
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        
        // 更新popover内容
        let menuView = MenuBarView(onToggleRecording: { [weak self] in
            self?.toggleRecording()
            self?.popover?.close()
        })
            .environmentObject(speechRecognizer)
            .environmentObject(hotkeyManager)
        
        popover?.contentViewController = NSHostingController(rootView: menuView)
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    
    // MARK: - 更新图标状态
    
    func updateStatusIcon() {
        let iconName = speechRecognizer.isRecording ? "waveform" : "mic.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Ummm")
    }
    
    func startRecording() {
        guard !speechRecognizer.isRecording else { return }
        
        Task { @MainActor in
            // 显示浮动指示器
            showFloatingIndicator()
            speechRecognizer.startRecording()
            updateStatusIcon()
        }
    }
    
    func stopRecording() {
        guard speechRecognizer.isRecording else { return }
        
        Task { @MainActor in
            speechRecognizer.stopRecording()
            updateStatusIcon()
            
            // 等待语音识别完成
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // 获取最终文本
            let finalText = speechRecognizer.transcript
            
            if !finalText.isEmpty {
                // 先复制到剪贴板
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
                
                // 再模拟粘贴插入
                TypeSimulator.pasteText()
                
                // 等待粘贴完成后再清空
                try? await Task.sleep(nanoseconds: 400_000_000)
                speechRecognizer.clearTranscript()
            }
            
            // 隐藏浮动指示器
            hideFloatingIndicator()
        }
    }
    
    func toggleRecording() {
        if speechRecognizer.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func showFloatingIndicator() {
        if floatingWindow == nil {
            floatingWindow = FloatingIndicatorWindow(speechRecognizer: speechRecognizer)
            floatingWindow?.onClose = { [weak self] in
                self?.stopRecording()
                self?.hideFloatingIndicator()
            }
        } else {
            floatingWindow?.updateContent()
        }
        floatingWindow?.show()
    }
    
    func hideFloatingIndicator() {
        floatingWindow?.hide()
    }
}

// MARK: - 模拟键盘输入

class TypeSimulator {
    /// 模拟 Cmd+V 粘贴
    static func pasteText() {
        // 方法1: 使用 CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)
        
        // 按下 Cmd+V
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cgSessionEventTap)
        }
        
        // 释放 Cmd+V
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cgSessionEventTap)
        }
    }
    
    /// 复制文本并模拟粘贴
    static func typeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteText()
        }
    }
}
