import Foundation

// 阿里云 Fun-ASR WebSocket 测试
let apiKey = "sk-f1bde991ec4b4327a17554568b4b7c4b"
let wsURL = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference/")!

class ASRTest: NSObject, URLSessionWebSocketDelegate {
    var webSocketTask: URLSessionWebSocketTask?
    let taskId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    
    func test() {
        print("🔗 正在连接 WebSocket...")
        
        var request = URLRequest(url: wsURL)
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // 等待连接
        Thread.sleep(forTimeInterval: 2)
        
        // 发送 run-task 指令
        sendRunTask()
        
        // 接收消息
        receiveMessages()
        
        // 保持运行
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
    }
    
    func sendRunTask() {
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
                "input": [:]
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: runTask),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 发送 run-task 指令...")
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ 发送失败: \(error)")
                } else {
                    print("✅ run-task 已发送")
                }
            }
        }
    }
    
    func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let header = json["header"] as? [String: Any],
                       let event = header["event"] as? String {
                        
                        switch event {
                        case "task-started":
                            print("✅ 任务已启动！API 连接正常")
                            print("📝 task_id: \(self?.taskId ?? "")")
                            // 发送 finish-task 结束测试
                            self?.sendFinishTask()
                            
                        case "task-finished":
                            print("✅ 任务已完成")
                            print("\n🎉 API 测试成功！可以接入项目")
                            exit(0)
                            
                        case "task-failed":
                            let errorMsg = header["error_message"] as? String ?? "未知错误"
                            print("❌ 任务失败: \(errorMsg)")
                            exit(1)
                            
                        default:
                            print("📨 收到事件: \(event)")
                        }
                    }
                default:
                    break
                }
                // 继续接收
                self?.receiveMessages()
                
            case .failure(let error):
                print("❌ 接收失败: \(error)")
            }
        }
    }
    
    func sendFinishTask() {
        let finishTask: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [:]
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: finishTask),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("❌ finish-task 发送失败: \(error)")
                }
            }
        }
    }
    
    // URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket 已连接")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket 已断开")
    }
}

// 运行测试
let test = ASRTest()
test.test()
