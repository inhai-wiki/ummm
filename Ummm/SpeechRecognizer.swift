import Foundation
import Speech
import AVFoundation
import AppKit

/// 语音识别管理器 - 负责实时语音转文字
@MainActor
class SpeechRecognizer: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 识别出的文字
    @Published var transcript: String = ""
    
    /// 是否正在录音
    @Published var isRecording: Bool = false
    
    /// 是否正在识别中（loading状态）
    @Published var isProcessing: Bool = false
    
    /// 错误信息
    @Published var errorMessage: String?
    
    /// 授权状态
    @Published var isAuthorized: Bool = false
    
    /// 当前使用的识别引擎
    @Published var currentEngine: String = "system"
    
    /// 音量级别 (0-1)
    @Published var audioLevel: Float = 0
    
    // MARK: - Settings
    
    /// 阿里云 API Key
    static let apiKeyKey = "AliyunASRAPIKey"
    
    var aliyunAPIKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? "" }
        set { 
            UserDefaults.standard.set(newValue, forKey: Self.apiKeyKey)
            objectWillChange.send()
        }
    }
    
    /// 是否使用阿里云 ASR
    var useAliyunASR: Bool {
        !aliyunAPIKey.isEmpty
    }
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    
    /// 静音超时计时器
    private var silenceTimer: Timer?
    /// 上次识别结果时间
    private var lastResultTime: Date?
    /// 静音超时时间（秒）
    private let silenceTimeout: TimeInterval = 3.0
    
    /// 阿里云 ASR 已确认的文本
    private var confirmedText: String = ""
    
    // MARK: - Initialization
    
    init() {
        // 初始化语音识别器，使用中文（简体）
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        
        // 如果中文不可用，尝试使用系统默认语言
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer()
        }
        
        // 设置阿里云 ASR 回调
        setupAliyunASRCallbacks()
    }
    
    private func setupAliyunASRCallbacks() {
        AliyunASR.shared.onTranscript = { [weak self] text, isFinal in
            Task { @MainActor in
                guard let self = self else { return }
                if isFinal {
                    // 最终结果，追加到已确认文本
                    self.confirmedText += text
                    self.transcript = self.confirmedText
                } else {
                    // 中间结果，显示已确认 + 当前识别中
                    self.transcript = self.confirmedText + text
                }
                self.isProcessing = true
                self.lastResultTime = Date()
            }
        }
        
        AliyunASR.shared.onError = { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error
            }
        }
        
        AliyunASR.shared.onStarted = { [weak self] in
            Task { @MainActor in
                self?.currentEngine = "aliyun"
            }
        }
        
        AliyunASR.shared.onStopped = { [weak self] in
            Task { @MainActor in
                self?.isRecording = false
                self?.isProcessing = false
                self?.audioLevel = 0
            }
        }
        
        AliyunASR.shared.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// 请求语音识别和麦克风权限
    func requestAuthorization() {
        // 先检查当前状态，已授权则不再请求
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        
        switch currentStatus {
        case .authorized:
            Task { @MainActor in
                self.isAuthorized = true
                self.errorMessage = nil
            }
        case .notDetermined:
            // 只有未决定时才请求授权
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    switch status {
                    case .authorized:
                        self?.isAuthorized = true
                        self?.errorMessage = nil
                    case .denied:
                        self?.isAuthorized = false
                        self?.errorMessage = "语音识别权限被拒绝，请在系统设置中开启"
                    case .restricted:
                        self?.isAuthorized = false
                        self?.errorMessage = "语音识别在此设备上受限"
                    case .notDetermined:
                        self?.isAuthorized = false
                        self?.errorMessage = "语音识别权限未确定"
                    @unknown default:
                        self?.isAuthorized = false
                        self?.errorMessage = "未知的授权状态"
                    }
                }
            }
        case .denied:
            Task { @MainActor in
                self.isAuthorized = false
                self.errorMessage = "语音识别权限被拒绝，请在系统设置中开启"
            }
        case .restricted:
            Task { @MainActor in
                self.isAuthorized = false
                self.errorMessage = "语音识别在此设备上受限"
            }
        @unknown default:
            Task { @MainActor in
                self.isAuthorized = false
                self.errorMessage = "未知的授权状态"
            }
        }
    }
    
    /// 开始录音和语音识别
    func startRecording() {
        // 如果已经在录音，先停止
        if isRecording {
            stopRecording()
            return
        }
        
        // 清空之前的文本
        transcript = ""
        confirmedText = ""
        isProcessing = true
        lastResultTime = Date()
        
        // 根据是否有 API Key 选择识别引擎
        if useAliyunASR {
            // 使用阿里云 ASR
            currentEngine = "aliyun"
            isRecording = true
            AliyunASR.shared.startRecognition(apiKey: aliyunAPIKey)
        } else {
            // 使用系统语音识别
            currentEngine = "system"
            
            // 检查麦克风权限状态
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            switch micStatus {
            case .authorized:
                break // 已授权，继续
            case .notDetermined:
                // 首次使用，请求麦克风权限
                isProcessing = false
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    Task { @MainActor in
                        if granted {
                            self?.startRecording() // 授权后重试
                        } else {
                            self?.errorMessage = "请在系统设置中开启麦克风权限"
                        }
                    }
                }
                return
            case .denied, .restricted:
                errorMessage = "请在系统设置中开启麦克风权限"
                isProcessing = false
                return
            @unknown default:
                isProcessing = false
                return
            }
            
            // 检查语音识别权限状态
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            switch speechStatus {
            case .authorized:
                isAuthorized = true
            case .notDetermined:
                // 首次使用，请求权限
                isProcessing = false
                SFSpeechRecognizer.requestAuthorization { [weak self] status in
                    Task { @MainActor in
                        if status == .authorized {
                            self?.isAuthorized = true
                            self?.startRecording() // 授权后重试
                        } else {
                            self?.isAuthorized = false
                            self?.errorMessage = "请在系统设置中开启语音识别权限"
                        }
                    }
                }
                return
            case .denied, .restricted:
                isAuthorized = false
                errorMessage = "请在系统设置中开启语音识别权限"
                isProcessing = false
                return
            @unknown default:
                isAuthorized = false
                isProcessing = false
                return
            }
            
            // 检查语音识别器是否可用
            guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
                errorMessage = "语音识别服务当前不可用"
                isProcessing = false
                return
            }
            
            do {
                try startSystemRecognition()
            } catch {
                errorMessage = "启动语音识别失败: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
    
    /// 停止录音
    func stopRecording() {
        if currentEngine == "aliyun" {
            AliyunASR.shared.stopRecognition()
        } else {
            stopSystemRecording()
        }
    }
    
    private func stopSystemRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // 先停止音频引擎
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // 完全清理
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        lastResultTime = nil
        
        isRecording = false
        isProcessing = false
        audioLevel = 0
    }
    
    /// 清除已识别的文字
    func clearTranscript() {
        transcript = ""
    }
    
    /// 复制文字到剪贴板
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }
    
    // MARK: - Private Methods
    
    private func startSystemRecognition() throws {
        // 先完全清理之前的状态
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        
        // 创建音频引擎
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建音频引擎"])
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建识别请求"])
        }
        
        // 配置识别请求
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        // 如果支持设备端识别，优先使用
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // 获取输入节点
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 检查采样率是否有效
        guard recordingFormat.sampleRate > 0 else {
            throw NSError(domain: "SpeechRecognizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "无效的音频格式，请检查麦克风设置"])
        }
        
        // 开始识别任务
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    self.isProcessing = !result.bestTranscription.formattedString.isEmpty
                    self.lastResultTime = Date()
                    
                    // 如果识别完成，自动重新开始新的识别任务以支持连续识别
                    if result.isFinal && self.isRecording {
                        // 结果已经确定，需要重新创建识别任务
                        self.restartRecognition()
                    }
                }
                
                if let error = error as NSError? {
                    // 如果还在录音中，尝试重新启动识别
                    if self.isRecording {
                        // 忽略正常的停止错误，尝试重启
                        if error.domain == "kAFAssistantErrorDomain" && (error.code == 1110 || error.code == 216 || error.code == 209) {
                            self.restartRecognition()
                        } else {
                            self.errorMessage = "识别错误: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        
        // 安装音频tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
            
            // 计算音量级别
            if let channelData = buffer.floatChannelData {
                let frames = buffer.frameLength
                var sum: Float = 0
                for i in 0..<Int(frames) {
                    sum += abs(channelData[0][i])
                }
                let avgLevel = sum / Float(frames)
                let normalizedLevel = min(avgLevel * 5, 1.0)
                Task { @MainActor in
                    self.audioLevel = normalizedLevel
                }
            }
        }
        
        // 准备并启动音频引擎
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        errorMessage = nil
        
        // 启动静音检测计时器
        startSilenceTimer()
    }
    
    /// 重新启动识别任务（支持连续识别）
    private func restartRecognition() {
        guard isRecording else { return }
        
        // 保留当前音频引擎，只重建识别任务
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // 创建新的识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        if #available(macOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        // 重新启动识别任务
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let result = result {
                    // 追加新识别的文本
                    let newText = result.bestTranscription.formattedString
                    if !newText.isEmpty {
                        if !self.transcript.isEmpty && !self.transcript.hasSuffix(" ") {
                            self.transcript += " "
                        }
                        // 替换或追加
                        self.transcript = self.transcript.trimmingCharacters(in: .whitespaces) + " " + newText
                    }
                    self.isProcessing = true
                    self.lastResultTime = Date()
                    
                    if result.isFinal && self.isRecording {
                        self.restartRecognition()
                    }
                }
                
                if let error = error as NSError? {
                    if self.isRecording {
                        if error.domain == "kAFAssistantErrorDomain" && (error.code == 1110 || error.code == 216 || error.code == 209) {
                            // 延迟一下再重启，避免过于频繁
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.restartRecognition()
                            }
                        }
                    }
                }
            }
        }
        
        // 重新安装音频tap
        guard let audioEngine = audioEngine else { return }
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 先移除旧的tap
        inputNode.removeTap(onBus: 0)
        
        // 安装新的tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
    }
    
    /// 启动静音检测计时器
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRecording else { return }
                
                if let lastTime = self.lastResultTime {
                    let elapsed = Date().timeIntervalSince(lastTime)
                    
                    // 如果超过静音时间且有文本，自动停止
                    if elapsed > self.silenceTimeout && !self.transcript.isEmpty {
                        self.stopRecording()
                    }
                }
            }
        }
    }
}
