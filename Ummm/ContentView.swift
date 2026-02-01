import SwiftUI
import AppKit

// MARK: - 浮动指示器窗口（Typeless风格 - 极简）

class FloatingIndicatorWindow: NSObject {
    private var window: NSWindow?
    private var speechRecognizer: SpeechRecognizer
    var onClose: (() -> Void)?
    
    init(speechRecognizer: SpeechRecognizer) {
        self.speechRecognizer = speechRecognizer
        super.init()
        setupWindow()
    }
    
    private func setupWindow() {
        let contentView = FloatingIndicatorView(
            speechRecognizer: speechRecognizer,
            onClose: { [weak self] in
                self?.onClose?()
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window?.contentView = hostingView
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window?.isMovableByWindowBackground = true
        window?.hasShadow = true
        window?.ignoresMouseEvents = false
        
        // 居中显示在屏幕底部
        centerWindow()
    }
    
    func updateContent() {
        let contentView = FloatingIndicatorView(
            speechRecognizer: speechRecognizer,
            onClose: { [weak self] in
                self?.onClose?()
            }
        )
        window?.contentView = NSHostingView(rootView: contentView)
    }
    
    private func centerWindow() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window?.frame ?? .zero
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.minY + 80
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    func show() {
        centerWindow()
        window?.orderFront(nil)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - 浮动指示器视图（简洁美观）

struct FloatingIndicatorView: View {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @State private var showCopied = false
    @State private var showInserted = false
    @State private var dots = ""
    var onClose: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            // 上半部分：状态和波形 + 关闭按钮
            HStack(spacing: 16) {
                // 波形动画
                WaveformView(isAnimating: true, audioLevel: speechRecognizer.audioLevel)
                    .frame(width: 50, height: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在聆听...")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("松开快捷键或静音自动停止")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // 关闭按钮
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            
            // 下半部分：识别文本或loading
            VStack(alignment: .leading, spacing: 10) {
                if speechRecognizer.transcript.isEmpty && speechRecognizer.isProcessing {
                    // Loading状态
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("识别中\(dots)")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .onAppear { startDotsAnimation() }
                    }
                } else if !speechRecognizer.transcript.isEmpty {
                    // 识别文本 - 最多2行，自动滚动到底部
                    GeometryReader { _ in
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                Text(speechRecognizer.transcript)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("transcriptEnd")
                            }
                            .onAppear {
                                proxy.scrollTo("transcriptEnd", anchor: .bottom)
                            }
                            .onChange(of: speechRecognizer.transcript) { _ in
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo("transcriptEnd", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(height: 38) // 约2行高度
                    .frame(maxWidth: .infinity)
                    
                    // 按钮组 - 右下角
                    HStack {
                        Spacer()
                        
                        // 插入按钮
                        Button(action: insertText) {
                            HStack(spacing: 4) {
                                Image(systemName: showInserted ? "checkmark" : "text.cursor")
                                    .font(.system(size: 11))
                                Text(showInserted ? "已插入" : "插入")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(showInserted ? .green : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(showInserted ? Color.green.opacity(0.2) : Color(hex: "6366F1").opacity(0.3))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 复制按钮
                        Button(action: copyText) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                Text(showCopied ? "已复制" : "复制")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(showCopied ? .green : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(showCopied ? Color.green.opacity(0.2) : Color.white.opacity(0.15))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    // 等待说话
                    Text("请开始说话...")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.88))
                .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(speechRecognizer.transcript, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
    
    private func insertText() {
        TypeSimulator.typeText(speechRecognizer.transcript)
        showInserted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showInserted = false
        }
    }
    
    private func startDotsAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            if dots.count >= 3 {
                dots = ""
            } else {
                dots += "."
            }
        }
    }
}

// MARK: - 波形动画视图

struct WaveformView: View {
    let isAnimating: Bool
    var audioLevel: Float = 0  // 0-1 音量级别
    
    @State private var animationValues: [CGFloat] = [0.2, 0.2, 0.2, 0.2, 0.2]
    @State private var idleTimer: Timer?
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 3, height: animationValues[index] * 24)
            }
        }
        .onChange(of: audioLevel) { newLevel in
            updateWaveform(level: newLevel)
        }
        .onAppear {
            if isAnimating {
                startIdleAnimation()
            }
        }
        .onDisappear {
            idleTimer?.invalidate()
            idleTimer = nil
        }
    }
    
    private func updateWaveform(level: Float) {
        // 放大音量响应，让波形更明显
        let amplifiedLevel = CGFloat(min(level * 2.5, 1.0))
        let baseLevel = CGFloat(max(amplifiedLevel, 0.15))
        withAnimation(.easeOut(duration: 0.08)) {
            animationValues = (0..<5).map { _ in
                baseLevel + CGFloat.random(in: 0...0.5) * amplifiedLevel
            }
        }
    }
    
    private func startIdleAnimation() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            // 波形微小呼吸动画
            withAnimation(.easeInOut(duration: 0.12)) {
                animationValues = animationValues.map { _ in
                    CGFloat.random(in: 0.12...0.25)
                }
            }
        }
        idleTimer = timer
    }
}

// MARK: - 菜单栏视图（简洁版 - 只保留设置）

struct MenuBarView: View {
    @EnvironmentObject var speechRecognizer: SpeechRecognizer
    @EnvironmentObject var hotkeyManager: HotkeyManager
    var onToggleRecording: (() -> Void)?
    @State private var isRecordingHotkey = false
    @State private var localMonitor: Any?
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false
    
    var body: some View {
        VStack(spacing: 0) {
            // API Key 设置
            apiKeySection
            
            Divider()
            
            // 快捷键设置
            hotkeyRow
            
            Divider()
            
            // 操作菜单
            VStack(spacing: 0) {
                MenuRow(icon: "gear", title: "系统权限") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                MenuRow(icon: "power", title: "退出", isDestructive: true) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            apiKeyInput = speechRecognizer.aliyunAPIKey
        }
    }
    
    // MARK: - API Key 设置
    
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("识别引擎")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 当前引擎状态
                Text(speechRecognizer.useAliyunASR ? "阿里云" : "系统")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(speechRecognizer.useAliyunASR ? Color.blue : Color.gray)
                    )
            }
            
            // API Key 输入框
            HStack(spacing: 6) {
                if showAPIKey {
                    TextField("API Key", text: $apiKeyInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .onSubmit {
                            speechRecognizer.aliyunAPIKey = apiKeyInput
                        }
                } else {
                    Text(apiKeyInput.isEmpty ? "未设置（使用系统识别）" : "••••••\(apiKeyInput.suffix(6))")
                        .font(.system(size: 11))
                        .foregroundColor(apiKeyInput.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                }
                
                // 显示/隐藏按钮
                Button(action: { 
                    showAPIKey.toggle()
                    if !showAPIKey {
                        speechRecognizer.aliyunAPIKey = apiKeyInput
                    }
                }) {
                    Image(systemName: showAPIKey ? "checkmark" : "pencil")
                        .font(.system(size: 10))
                        .foregroundColor(showAPIKey ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            
            // 提示文字 + 前往获取链接
            VStack(alignment: .leading, spacing: 4) {
                if apiKeyInput.isEmpty {
                    Text("想要更精准的识别体验？")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        if let url = URL(string: "https://bailian.console.aliyun.com/cn-beijing/?source_channel=%22ummm%22?tab=app#/api-key") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("前往阿里云百炼获取 API Key")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "6366F1"))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                } else {
                    Text("已启用阿里云识别引擎")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
    }
    
    // MARK: - 快捷键行
    
    private var hotkeyRow: some View {
        HStack {
            Text("快捷键")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { toggleHotkeyRecording() }) {
                Text(isRecordingHotkey ? "按下新键..." : hotkeyManager.currentHotkey.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(isRecordingHotkey ? Color(hex: "6366F1") : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .onDisappear { removeHotkeyMonitor() }
    }
    
    private func toggleHotkeyRecording() {
        isRecordingHotkey.toggle()
        if isRecordingHotkey {
            hotkeyManager.startRecordingHotkey()
            setupHotkeyMonitor()
        } else {
            hotkeyManager.stopRecordingHotkey()
            removeHotkeyMonitor()
        }
    }
    
    private func setupHotkeyMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if isRecordingHotkey {
                if hotkeyManager.recordHotkey(from: event) {
                    DispatchQueue.main.async {
                        isRecordingHotkey = false
                        removeHotkeyMonitor()
                    }
                }
                return nil
            }
            return event
        }
    }
    
    private func removeHotkeyMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

// MARK: - 菜单行

struct MenuRow: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(isDestructive ? .red : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.5) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
