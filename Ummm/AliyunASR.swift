import Foundation
import AVFoundation

// MARK: - 阿里云 Fun-ASR 实时语音识别服务

class AliyunASR: NSObject, URLSessionWebSocketDelegate {
    static let shared = AliyunASR()
    
    private let wsURL = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference/")!
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var taskId: String = ""
    private var isRunning = false
    
    // 回调
    var onTranscript: ((String, Bool) -> Void)?  // (文本, 是否最终结果)
    var onError: ((String) -> Void)?
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?  // 音量级别 0-1
    
    private override init() {
        super.init()
    }
    
    // MARK: - 公开方法
    
    func startRecognition(apiKey: String) {
        guard !isRunning else { return }
        isRunning = true
        taskId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        
        // 建立 WebSocket 连接
        var request = URLRequest(url: wsURL)
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // 开始接收消息
        receiveMessages()
        
        // 延迟发送 run-task（等待连接建立）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendRunTask()
        }
    }
    
    func stopRecognition() {
        guard isRunning else { return }
        isRunning = false
        
        // 停止音频采集
        stopAudioCapture()
        
        // 发送 finish-task
        sendFinishTask()
        
        // 延迟关闭连接
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self?.webSocketTask = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onStopped?()
        }
    }
    
    // MARK: - WebSocket 消息处理
    
    private func sendRunTask() {
        let runTask: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": "fun-asr-realtime",
                "parameters": [
                    "format": "pcm",
                    "sample_rate": 16000
                ],
                "input": [:] as [String: Any]
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: runTask),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.onError?("发送指令失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func sendFinishTask() {
        let finishTask: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [:] as [String: Any]
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: finishTask),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { _ in }
        }
    }
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default:
                    break
                }
                // 继续接收
                if self.isRunning {
                    self.receiveMessages()
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.onError?("接收失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event = header["event"] as? String else { return }
        
        switch event {
        case "task-started":
            DispatchQueue.main.async { [weak self] in
                self?.onStarted?()
            }
            // 开始音频采集
            startAudioCapture()
            
        case "result-generated":
            if let payload = json["payload"] as? [String: Any],
               let output = payload["output"] as? [String: Any],
               let sentence = output["sentence"] as? [String: Any],
               let text = sentence["text"] as? String {
                let isFinal = sentence["sentence_end"] as? Bool ?? false
                DispatchQueue.main.async { [weak self] in
                    self?.onTranscript?(text, isFinal)
                }
            }
            
        case "task-finished":
            DispatchQueue.main.async { [weak self] in
                self?.onStopped?()
            }
            
        case "task-failed":
            let errorMsg = header["error_message"] as? String ?? "未知错误"
            DispatchQueue.main.async { [weak self] in
                self?.onError?(errorMsg)
                self?.onStopped?()
            }
            
        default:
            break
        }
    }
    
    // MARK: - 音频采集
    
    private func startAudioCapture() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // 转换为 16kHz PCM
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        
        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            onError?("无法创建音频转换器")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1600, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }
        
        do {
            try audioEngine.start()
        } catch {
            onError?("音频引擎启动失败: \(error.localizedDescription)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // 计算音量级别
        if let channelData = buffer.floatChannelData {
            let frames = buffer.frameLength
            var sum: Float = 0
            for i in 0..<Int(frames) {
                sum += abs(channelData[0][i])
            }
            let avgLevel = sum / Float(frames)
            // 归一化到 0-1
            let normalizedLevel = min(avgLevel * 5, 1.0)
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevel?(normalizedLevel)
            }
        }
        
        // 计算输出帧数
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard status != .error, error == nil else { return }
        
        // 发送 PCM 数据
        if let channelData = outputBuffer.int16ChannelData {
            let data = Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 2)
            webSocketTask?.send(.data(data)) { _ in }
        }
    }
    
    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // 连接已建立
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.onStopped?()
        }
    }
}
