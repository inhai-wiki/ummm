本文介绍如何通过WebSocket协议直接接入Fun-ASR实时语音识别服务。该方式适用于所有支持WebSocket的编程语言。为简化Java和Python开发者的接入流程，我们另提供了封装度更高的SDK（[Python SDK](https://help.aliyun.com/zh/model-studio/fun-asr-realtime-python-sdk)/[Java SDK](https://help.aliyun.com/zh/model-studio/fun-asr-realtime-java-sdk)），但您仍可选择使用本文描述的通用协议进行开发，以获得最大的灵活性。

**用户指南：**关于模型介绍和选型建议请参见[实时语音识别-Fun-ASR/Gummy/Paraformer](https://help.aliyun.com/zh/model-studio/real-time-speech-recognition)。

## **快速开始**

### **准备工作**

1.  [获取与配置 API Key](https://help.aliyun.com/zh/model-studio/get-api-key)，为安全起见，推荐将API Key配置到环境变量。
    
2.  下载示例音频文件：[asr\_example.wav](https://help-static-aliyun-doc.aliyuncs.com/file-manage-files/zh-CN/20241114/mgiguo/asr_example.wav)。
    

### **示例代码**

## Node.js

需安装相关依赖：

```
npm install ws
npm install uuid
```

示例代码如下：

```
const fs = require('fs');
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid'); // 用于生成UUID

// 新加坡和北京地域的API Key不同。获取API Key：https://help.aliyun.com/zh/model-studio/get-api-key
// 若没有配置环境变量，请用百炼API Key将下行替换为：const apiKey = "sk-xxx"
const apiKey = process.env.DASHSCOPE_API_KEY;
// 以下为北京地域url，若使用新加坡地域的模型，需将url替换为：wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference/
const url = 'wss://dashscope.aliyuncs.com/api-ws/v1/inference/'; // WebSocket服务器地址
const audioFile = 'asr_example.wav'; // 替换为您的音频文件路径

// 生成32位随机ID
const TASK_ID = uuidv4().replace(/-/g, '').slice(0, 32);

// 创建WebSocket客户端
const ws = new WebSocket(url, {
  headers: {
    Authorization: `bearer ${apiKey}`
  }
});

let taskStarted = false; // 标记任务是否已启动

// 连接打开时发送run-task指令
ws.on('open', () => {
  console.log('连接到服务器');
  sendRunTask();
});

// 接收消息处理
ws.on('message', (data) => {
  const message = JSON.parse(data);
  switch (message.header.event) {
    case 'task-started':
      console.log('任务开始');
      taskStarted = true;
      sendAudioStream();
      break;
    case 'result-generated':
      console.log('识别结果：', message.payload.output.sentence.text);
      if (message.payload.usage) {
        console.log('任务计费时长（秒）：', message.payload.usage.duration);
      }
      break;
    case 'task-finished':
      console.log('任务完成');
      ws.close();
      break;
    case 'task-failed':
      console.error('任务失败：', message.header.error_message);
      ws.close();
      break;
    default:
      console.log('未知事件：', message.header.event);
  }
});

// 如果没有收到task-started事件，关闭连接
ws.on('close', () => {
  if (!taskStarted) {
    console.error('任务未启动，关闭连接');
  }
});

// 发送run-task指令
function sendRunTask() {
  const runTaskMessage = {
    header: {
      action: 'run-task',
      task_id: TASK_ID,
      streaming: 'duplex'
    },
    payload: {
      task_group: 'audio',
      task: 'asr',
      function: 'recognition',
      model: 'fun-asr-realtime',
      parameters: {
        sample_rate: 16000,
        format: 'wav'
      },
      input: {}
    }
  };
  ws.send(JSON.stringify(runTaskMessage));
}

// 发送音频流
function sendAudioStream() {
  const audioStream = fs.createReadStream(audioFile);
  let chunkCount = 0;

  function sendNextChunk() {
    const chunk = audioStream.read();
    if (chunk) {
      ws.send(chunk);
      chunkCount++;
      setTimeout(sendNextChunk, 100); // 每100ms发送一次
    }
  }

  audioStream.on('readable', () => {
    sendNextChunk();
  });

  audioStream.on('end', () => {
    console.log('音频流结束');
    sendFinishTask();
  });

  audioStream.on('error', (err) => {
    console.error('读取音频文件错误：', err);
    ws.close();
  });
}

// 发送finish-task指令
function sendFinishTask() {
  const finishTaskMessage = {
    header: {
      action: 'finish-task',
      task_id: TASK_ID,
      streaming: 'duplex'
    },
    payload: {
      input: {}
    }
  };
  ws.send(JSON.stringify(finishTaskMessage));
}

// 错误处理
ws.on('error', (error) => {
  console.error('WebSocket错误：', error);
});
```

## C#

示例代码如下：

```
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

class Program {
    private static ClientWebSocket _webSocket = new ClientWebSocket();
    private static CancellationTokenSource _cancellationTokenSource = new CancellationTokenSource();
    private static bool _taskStartedReceived = false;
    private static bool _taskFinishedReceived = false;
    // 新加坡和北京地域的API Key不同。获取API Key：https://help.aliyun.com/zh/model-studio/get-api-key
    // 若没有配置环境变量，请用百炼API Key将下行替换为：private static readonly string ApiKey = "sk-xxx"
    private static readonly string ApiKey = Environment.GetEnvironmentVariable("DASHSCOPE_API_KEY") ?? throw new InvalidOperationException("DASHSCOPE_API_KEY environment variable is not set.");

    // 以下为北京地域url，若使用新加坡地域的模型，需将url替换为：wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference/
    private const string WebSocketUrl = "wss://dashscope.aliyuncs.com/api-ws/v1/inference/";
    // 替换为您的音频文件路径
    private const string AudioFilePath = "asr_example.wav";

    static async Task Main(string[] args) {
        // 建立WebSocket连接，配置headers进行鉴权
        _webSocket.Options.SetRequestHeader("Authorization", $"bearer {ApiKey}");

        await _webSocket.ConnectAsync(new Uri(WebSocketUrl), _cancellationTokenSource.Token);

        // 启动线程异步接收WebSocket消息
        var receiveTask = ReceiveMessagesAsync();

        // 发送run-task指令
        string _taskId = Guid.NewGuid().ToString("N"); // 生成32位随机ID
        var runTaskJson = GenerateRunTaskJson(_taskId);
        await SendAsync(runTaskJson);

        // 等待task-started事件
        while (!_taskStartedReceived) {
            await Task.Delay(100, _cancellationTokenSource.Token);
        }

        // 读取本地文件，向服务器发送待识别音频流
        await SendAudioStreamAsync(AudioFilePath);

        // 发送finish-task指令结束任务
        var finishTaskJson = GenerateFinishTaskJson(_taskId);
        await SendAsync(finishTaskJson);

        // 等待task-finished事件
        while (!_taskFinishedReceived && !_cancellationTokenSource.IsCancellationRequested) {
            try {
                await Task.Delay(100, _cancellationTokenSource.Token);
            } catch (OperationCanceledException) {
                // 任务已被取消，退出循环
                break;
            }
        }

        // 关闭连接
        if (!_cancellationTokenSource.IsCancellationRequested) {
            await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", _cancellationTokenSource.Token);
        }

        _cancellationTokenSource.Cancel();
        try {
            await receiveTask;
        } catch (OperationCanceledException) {
            // 忽略操作取消异常
        }
    }

    private static async Task ReceiveMessagesAsync() {
        try {
            while (_webSocket.State == WebSocketState.Open && !_cancellationTokenSource.IsCancellationRequested) {
                var message = await ReceiveMessageAsync(_cancellationTokenSource.Token);
                if (message != null) {
                    var eventValue = message["header"]?["event"]?.GetValue<string>();
                    switch (eventValue) {
                        case "task-started":
                            Console.WriteLine("任务开启成功");
                            _taskStartedReceived = true;
                            break;
                        case "result-generated":
                            Console.WriteLine($"识别结果：{message["payload"]?["output"]?["sentence"]?["text"]?.GetValue<string>()}");
                            if (message["payload"]?["usage"] != null && message["payload"]?["usage"]?["duration"] != null) {
                                Console.WriteLine($"任务计费时长（秒）：{message["payload"]?["usage"]?["duration"]?.GetValue<int>()}");
                            }
                            break;
                        case "task-finished":
                            Console.WriteLine("任务完成");
                            _taskFinishedReceived = true;
                            _cancellationTokenSource.Cancel();
                            break;
                        case "task-failed":
                            Console.WriteLine($"任务失败：{message["header"]?["error_message"]?.GetValue<string>()}");
                            _cancellationTokenSource.Cancel();
                            break;
                    }
                }
            }
        } catch (OperationCanceledException) {
            // 忽略操作取消异常
        }
    }

    private static async Task<JsonNode?> ReceiveMessageAsync(CancellationToken cancellationToken) {
        var buffer = new byte[1024 * 4];
        var segment = new ArraySegment<byte>(buffer);
        var result = await _webSocket.ReceiveAsync(segment, cancellationToken);

        if (result.MessageType == WebSocketMessageType.Close) {
            await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", cancellationToken);
            return null;
        }

        var message = Encoding.UTF8.GetString(buffer, 0, result.Count);
        return JsonNode.Parse(message);
    }

    private static async Task SendAsync(string message) {
        var buffer = Encoding.UTF8.GetBytes(message);
        var segment = new ArraySegment<byte>(buffer);
        await _webSocket.SendAsync(segment, WebSocketMessageType.Text, true, _cancellationTokenSource.Token);
    }

    private static async Task SendAudioStreamAsync(string filePath) {
        using (var audioStream = File.OpenRead(filePath)) {
            var buffer = new byte[1024]; // 每次发送100ms的音频数据
            int bytesRead;

            while ((bytesRead = await audioStream.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                var segment = new ArraySegment<byte>(buffer, 0, bytesRead);
                await _webSocket.SendAsync(segment, WebSocketMessageType.Binary, true, _cancellationTokenSource.Token);
                await Task.Delay(100); // 间隔100ms
            }
        }
    }

    private static string GenerateRunTaskJson(string taskId) {
        var runTask = new JsonObject {
            ["header"] = new JsonObject {
                ["action"] = "run-task",
                ["task_id"] = taskId,
                ["streaming"] = "duplex"
            },
            ["payload"] = new JsonObject {
                ["task_group"] = "audio",
                ["task"] = "asr",
                ["function"] = "recognition",
                ["model"] = "fun-asr-realtime",
                ["parameters"] = new JsonObject {
                    ["format"] = "wav",
                    ["sample_rate"] = 16000,
                },
                ["input"] = new JsonObject()
            }
        };
        return JsonSerializer.Serialize(runTask);
    }

    private static string GenerateFinishTaskJson(string taskId) {
        var finishTask = new JsonObject {
            ["header"] = new JsonObject {
                ["action"] = "finish-task",
                ["task_id"] = taskId,
                ["streaming"] = "duplex"
            },
            ["payload"] = new JsonObject {
                ["input"] = new JsonObject()
            }
        };
        return JsonSerializer.Serialize(finishTask);
    }
}
```

## PHP

示例代码目录结构为：

my-php-project/

├── composer.json

├── vendor/

└── index.php

composer.json内容如下，相关依赖的版本号请根据实际情况自行决定：

```
{
    "require": {
        "react/event-loop": "^1.3",
        "react/socket": "^1.11",
        "react/stream": "^1.2",
        "react/http": "^1.1",
        "ratchet/pawl": "^0.4"
    },
    "autoload": {
        "psr-4": {
            "App\\": "src/"
        }
    }
}
```

index.php内容如下：

```
<?php

require __DIR__ . '/vendor/autoload.php';

use Ratchet\Client\Connector;
use React\EventLoop\Loop;
use React\Socket\Connector as SocketConnector;
use Ratchet\rfc6455\Messaging\Frame;

// 新加坡和北京地域的API Key不同。获取API Key：https://help.aliyun.com/zh/model-studio/get-api-key
// 若没有配置环境变量，请用百炼API Key将下行替换为：$api_key = "sk-xxx"
$api_key = getenv("DASHSCOPE_API_KEY");
// 以下为北京地域url，若使用新加坡地域的模型，需将url替换为：wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference/
$websocket_url = 'wss://dashscope.aliyuncs.com/api-ws/v1/inference/';
$audio_file_path = 'asr_example.wav'; // 替换为您的音频文件路径

$loop = Loop::get();

// 创建自定义的连接器
$socketConnector = new SocketConnector($loop, [
    'tcp' => [
        'bindto' => '0.0.0.0:0',
    ],
    'tls' => [
        'verify_peer' => false,
        'verify_peer_name' => false,
    ],
]);

$connector = new Connector($loop, $socketConnector);

$headers = [
    'Authorization' => 'bearer ' . $api_key
];

$connector($websocket_url, [], $headers)->then(function ($conn) use ($loop, $audio_file_path) {
    echo "连接到WebSocket服务器\n";

    // 启动异步接收WebSocket消息的线程
    $conn->on('message', function($msg) use ($conn, $loop, $audio_file_path) {
        $response = json_decode($msg, true);

        if (isset($response['header']['event'])) {
            handleEvent($conn, $response, $loop, $audio_file_path);
        } else {
            echo "未知的消息格式\n";
        }
    });

    // 监听连接关闭
    $conn->on('close', function($code = null, $reason = null) {
        echo "连接已关闭\n";
        if ($code !== null) {
            echo "关闭代码: " . $code . "\n";
        }
        if ($reason !== null) {
            echo "关闭原因：" . $reason . "\n";
        }
    });

    // 生成任务ID
    $taskId = generateTaskId();

    // 发送 run-task 指令
    sendRunTaskMessage($conn, $taskId);

}, function ($e) {
    echo "无法连接：{$e->getMessage()}\n";
});

$loop->run();

/**
 * 生成任务ID
 * @return string
 */
function generateTaskId(): string {
    return bin2hex(random_bytes(16));
}

/**
 * 发送 run-task 指令
 * @param $conn
 * @param $taskId
 */
function sendRunTaskMessage($conn, $taskId) {
    $runTaskMessage = json_encode([
        "header" => [
            "action" => "run-task",
            "task_id" => $taskId,
            "streaming" => "duplex"
        ],
        "payload" => [
            "task_group" => "audio",
            "task" => "asr",
            "function" => "recognition",
            "model" => "fun-asr-realtime",
            "parameters" => [
                "format" => "wav",
                "sample_rate" => 16000
            ],
            "input" => []
        ]
    ]);
    echo "准备发送run-task指令：" . $runTaskMessage . "\n";
    $conn->send($runTaskMessage);
    echo "run-task指令已发送\n";
}

/**
 * 读取音频文件
 * @param string $filePath
 * @return bool|string
 */
function readAudioFile(string $filePath) {
    $voiceData = file_get_contents($filePath);
    if ($voiceData === false) {
        echo "无法读取音频文件\n";
    }
    return $voiceData;
}

/**
 * 分割音频数据
 * @param string $data
 * @param int $chunkSize
 * @return array
 */
function splitAudioData(string $data, int $chunkSize): array {
    return str_split($data, $chunkSize);
}

/**
 * 发送 finish-task 指令
 * @param $conn
 * @param $taskId
 */
function sendFinishTaskMessage($conn, $taskId) {
    $finishTaskMessage = json_encode([
        "header" => [
            "action" => "finish-task",
            "task_id" => $taskId,
            "streaming" => "duplex"
        ],
        "payload" => [
            "input" => []
        ]
    ]);
    echo "准备发送finish-task指令: " . $finishTaskMessage . "\n";
    $conn->send($finishTaskMessage);
    echo "finish-task指令已发送\n";
}

/**
 * 处理事件
 * @param $conn
 * @param $response
 * @param $loop
 * @param $audio_file_path
 */
function handleEvent($conn, $response, $loop, $audio_file_path) {
    static $taskId;
    static $chunks;
    static $allChunksSent = false;

    if (is_null($taskId)) {
        $taskId = generateTaskId();
    }

    switch ($response['header']['event']) {
        case 'task-started':
            echo "任务开始，发送音频数据...\n";
            // 读取音频文件
            $voiceData = readAudioFile($audio_file_path);
            if ($voiceData === false) {
                echo "无法读取音频文件\n";
                $conn->close();
                return;
            }

            // 分割音频数据
            $chunks = splitAudioData($voiceData, 1024);

            // 定义发送函数
            $sendChunk = function() use ($conn, &$chunks, $loop, &$sendChunk, &$allChunksSent, $taskId) {
                if (!empty($chunks)) {
                    $chunk = array_shift($chunks);
                    $binaryMsg = new Frame($chunk, true, Frame::OP_BINARY);
                    $conn->send($binaryMsg);
                    // 100ms后发送下一个片段
                    $loop->addTimer(0.1, $sendChunk);
                } else {
                    echo "所有数据块已发送\n";
                    $allChunksSent = true;

                    // 发送 finish-task 指令
                    sendFinishTaskMessage($conn, $taskId);
                }
            };

            // 开始发送音频数据
            $sendChunk();
            break;
        case 'result-generated':
            $result = $response['payload']['output']['sentence'];
            echo "识别结果：" . $result['text'] . "\n";
            if (isset($response['payload']['usage']['duration'])) {
                echo "任务计费时长（秒）：" . $response['payload']['usage']['duration'] . "\n";
            }
            break;
        case 'task-finished':
            echo "任务完成\n";
            $conn->close();
            break;
        case 'task-failed':
            echo "任务失败\n";
            echo "错误代码：" . $response['header']['error_code'] . "\n";
            echo "错误信息：" . $response['header']['error_message'] . "\n";
            $conn->close();
            break;
        case 'error':
            echo "错误：" . $response['payload']['message'] . "\n";
            break;
        default:
            echo "未知事件：" . $response['header']['event'] . "\n";
            break;
    }

    // 如果所有数据已发送且任务已完成，关闭连接
    if ($allChunksSent && $response['header']['event'] == 'task-finished') {
        // 等待1秒以确保所有数据都已传输完毕
        $loop->addTimer(1, function() use ($conn) {
            $conn->close();
            echo "客户端关闭连接\n";
        });
    }
}
```

## Go

```
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

const (
	// 以下为北京地域url，若使用新加坡地域的模型，需将url替换为：wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference/
	wsURL     = "wss://dashscope.aliyuncs.com/api-ws/v1/inference/" // WebSocket服务器地址
	audioFile = "asr_example.wav"                                   // 替换为您的音频文件路径
)

var dialer = websocket.DefaultDialer

func main() {
	// 新加坡和北京地域的API Key不同。获取API Key：https://help.aliyun.com/zh/model-studio/get-api-key
    // 若没有配置环境变量，请用百炼API Key将下行替换为：apiKey := "sk-xxx"
	apiKey := os.Getenv("DASHSCOPE_API_KEY")

	// 连接WebSocket服务
	conn, err := connectWebSocket(apiKey)
	if err != nil {
		log.Fatal("连接WebSocket失败：", err)
	}
	defer closeConnection(conn)

	// 启动一个goroutine来接收结果
	taskStarted := make(chan bool)
	taskDone := make(chan bool)
	startResultReceiver(conn, taskStarted, taskDone)

	// 发送run-task指令
	taskID, err := sendRunTaskCmd(conn)
	if err != nil {
		log.Fatal("发送run-task指令失败：", err)
	}

	// 等待task-started事件
	waitForTaskStarted(taskStarted)

	// 发送待识别音频文件流
	if err := sendAudioData(conn); err != nil {
		log.Fatal("发送音频失败：", err)
	}

	// 发送finish-task指令
	if err := sendFinishTaskCmd(conn, taskID); err != nil {
		log.Fatal("发送finish-task指令失败：", err)
	}

	// 等待任务完成或失败
	<-taskDone
}

// 定义结构体来表示JSON数据
type Header struct {
	Action       string                 `json:"action"`
	TaskID       string                 `json:"task_id"`
	Streaming    string                 `json:"streaming"`
	Event        string                 `json:"event"`
	ErrorCode    string                 `json:"error_code,omitempty"`
	ErrorMessage string                 `json:"error_message,omitempty"`
	Attributes   map[string]interface{} `json:"attributes"`
}

type Output struct {
	Sentence struct {
		BeginTime int64  `json:"begin_time"`
		EndTime   *int64 `json:"end_time"`
		Text      string `json:"text"`
		Words     []struct {
			BeginTime   int64  `json:"begin_time"`
			EndTime     *int64 `json:"end_time"`
			Text        string `json:"text"`
			Punctuation string `json:"punctuation"`
		} `json:"words"`
	} `json:"sentence"`
}

type Payload struct {
	TaskGroup  string `json:"task_group"`
	Task       string `json:"task"`
	Function   string `json:"function"`
	Model      string `json:"model"`
	Parameters Params `json:"parameters"`
	Input      Input  `json:"input"`
	Output     Output `json:"output,omitempty"`
	Usage      *struct {
		Duration int `json:"duration"`
	} `json:"usage,omitempty"`
}

type Params struct {
	Format                   string `json:"format"`
	SampleRate               int    `json:"sample_rate"`
	VocabularyID             string `json:"vocabulary_id"`
	DisfluencyRemovalEnabled bool   `json:"disfluency_removal_enabled"`
}

type Input struct {
}

type Event struct {
	Header  Header  `json:"header"`
	Payload Payload `json:"payload"`
}

// 连接WebSocket服务
func connectWebSocket(apiKey string) (*websocket.Conn, error) {
	header := make(http.Header)
	header.Add("Authorization", fmt.Sprintf("bearer %s", apiKey))
	conn, _, err := dialer.Dial(wsURL, header)
	return conn, err
}

// 启动一个goroutine异步接收WebSocket消息
func startResultReceiver(conn *websocket.Conn, taskStarted chan<- bool, taskDone chan<- bool) {
	go func() {
		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				log.Println("解析服务器消息失败：", err)
				return
			}
			var event Event
			err = json.Unmarshal(message, &event)
			if err != nil {
				log.Println("解析事件失败：", err)
				continue
			}
			if handleEvent(conn, event, taskStarted, taskDone) {
				return
			}
		}
	}()
}

// 发送run-task指令
func sendRunTaskCmd(conn *websocket.Conn) (string, error) {
	runTaskCmd, taskID, err := generateRunTaskCmd()
	if err != nil {
		return "", err
	}
	err = conn.WriteMessage(websocket.TextMessage, []byte(runTaskCmd))
	return taskID, err
}

// 生成run-task指令
func generateRunTaskCmd() (string, string, error) {
	taskID := uuid.New().String()
	runTaskCmd := Event{
		Header: Header{
			Action:    "run-task",
			TaskID:    taskID,
			Streaming: "duplex",
		},
		Payload: Payload{
			TaskGroup: "audio",
			Task:      "asr",
			Function:  "recognition",
			Model:     "fun-asr-realtime",
			Parameters: Params{
				Format:     "wav",
				SampleRate: 16000,
			},
			Input: Input{},
		},
	}
	runTaskCmdJSON, err := json.Marshal(runTaskCmd)
	return string(runTaskCmdJSON), taskID, err
}

// 等待task-started事件
func waitForTaskStarted(taskStarted chan bool) {
	select {
	case <-taskStarted:
		fmt.Println("任务开启成功")
	case <-time.After(10 * time.Second):
		log.Fatal("等待task-started超时，任务开启失败")
	}
}

// 发送音频数据
func sendAudioData(conn *websocket.Conn) error {
	file, err := os.Open(audioFile)
	if err != nil {
		return err
	}
	defer file.Close()

	buf := make([]byte, 1024)
	for {
		n, err := file.Read(buf)
		if n == 0 {
			break
		}
		if err != nil && err != io.EOF {
			return err
		}
		err = conn.WriteMessage(websocket.BinaryMessage, buf[:n])
		if err != nil {
			return err
		}
		time.Sleep(100 * time.Millisecond)
	}
	return nil
}

// 发送finish-task指令
func sendFinishTaskCmd(conn *websocket.Conn, taskID string) error {
	finishTaskCmd, err := generateFinishTaskCmd(taskID)
	if err != nil {
		return err
	}
	err = conn.WriteMessage(websocket.TextMessage, []byte(finishTaskCmd))
	return err
}

// 生成finish-task指令
func generateFinishTaskCmd(taskID string) (string, error) {
	finishTaskCmd := Event{
		Header: Header{
			Action:    "finish-task",
			TaskID:    taskID,
			Streaming: "duplex",
		},
		Payload: Payload{
			Input: Input{},
		},
	}
	finishTaskCmdJSON, err := json.Marshal(finishTaskCmd)
	return string(finishTaskCmdJSON), err
}

// 处理事件
func handleEvent(conn *websocket.Conn, event Event, taskStarted chan<- bool, taskDone chan<- bool) bool {
	switch event.Header.Event {
	case "task-started":
		fmt.Println("收到task-started事件")
		taskStarted <- true
	case "result-generated":
		if event.Payload.Output.Sentence.Text != "" {
			fmt.Println("识别结果：", event.Payload.Output.Sentence.Text)
		}
		if event.Payload.Usage != nil {
			fmt.Println("任务计费时长（秒）：", event.Payload.Usage.Duration)
		}
	case "task-finished":
		fmt.Println("任务完成")
		taskDone <- true
		return true
	case "task-failed":
		handleTaskFailed(event, conn)
		taskDone <- true
		return true
	default:
		log.Printf("预料之外的事件：%v", event)
	}
	return false
}

// 处理任务失败事件
func handleTaskFailed(event Event, conn *websocket.Conn) {
	if event.Header.ErrorMessage != "" {
		log.Fatalf("任务失败：%s", event.Header.ErrorMessage)
	} else {
		log.Fatal("未知原因导致任务失败")
	}
}

// 关闭连接
func closeConnection(conn *websocket.Conn) {
	if conn != nil {
		conn.Close()
	}
}
```

## **核心概念**

### **交互时序**

客户端与服务端的交互遵循严格顺序，以保证任务正确执行。

![image](https://help-static-aliyun-doc.aliyuncs.com/assets/img/zh-CN/4977796671/CAEQURiBgMCczta5pxkiIGY0N2Q2YjIwZTM1MTQyNTY4ZmFkY2MwN2JmOTllODFl4709861_20241015153444.149.svg)

1.  **建立连接：**客户端向服务端发起WebSocket连接请求，并在请求头中携带鉴权信息。
    
2.  **开启任务：**连接成功后，客户端发送一条[run-task指令](#12d8a57443dmz)，声明要使用的模型和音频参数。
    
3.  **确认任务：**服务端返回[task-started事件](#2942cede42z9e)，表示已准备好接收音频。
    
4.  **传输数据：**
    
    -   客户端开始连续发送[二进制音频](#4fad5a12ed137)数据。
        
    -   服务端在识别过程中，会实时、多次地返回[result-generated事件](#e9420a4d7bock)，其中包含中间和最终识别结果。
        
5.  **结束任务：**音频发送完毕后，客户端发送[finish-task指令](#2e967d2d349es)。
    
6.  **确认结束：**服务端处理完所有剩余音频后，返回[task-finished事件](#f11a341732xug)，标志任务正常结束。
    
7.  **关闭连接：**客户端或服务端关闭WebSocket连接。
    

### **音频流规范**

-   声道：发送至服务端的二进制音频须为单声道。
    
-   格式与编码：支持pcm、wav、mp3、opus、speex、aac、amr格式。
    
    -   wav格式文件必须为PCM编码。
        
    -   opus或speex格式文件必须使用Ogg容器封装。
        
    -   amr格式仅支持AMR-NB类型。
        
-   采样率：必须与[run-task指令](#12d8a57443dmz)中指定的sample\_rate参数以及所选模型的要求一致。
    

## **模型列表**

### 中国大陆（北京）

| **模型名称** | **版本** | **支持的语言** | **支持的采样率** | **适用场景** | **支持的音频格式** | **单价** | **免费额度**[**（注）**](https://help.aliyun.com/zh/model-studio/new-free-quota#591f3dfedfyzj) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| fun-asr-realtime > 当前等同fun-asr-realtime-2025-11-07 | 稳定版 | 中文（普通话、粤语、吴语、闽南语、客家话、赣语、湘语、晋语；并支持中原、西南、冀鲁、江淮、兰银、胶辽、东北、北京、港台等，包括河南、陕西、湖北、四川、重庆、云南、贵州、广东、广西、河北、天津、山东、安徽、南京、江苏、杭州、甘肃、宁夏等地区官话口音）、英文、日语 | 16kHz | 视频直播、会议、电话客服等 | pcm、wav、mp3、opus、speex、aac、amr | 0.00033元/秒 | 36,000秒（10小时） 有效期：阿里云百炼开通后90天 |
| fun-asr-realtime-2025-11-07 > 相较fun-asr-realtime-2025-09-15做了远场VAD优化，识别更准 | 快照版 |
| fun-asr-realtime-2025-09-15 | 中文（普通话）、英文 |

### **国际（新加坡）**

| **模型名称** | **版本** | **支持的语言** | **支持的采样率** | **适用场景** | **支持的音频格式** | **单价** |
| --- | --- | --- | --- | --- | --- | --- |
| fun-asr-realtime > 当前等同fun-asr-realtime-2025-11-07 | 稳定版 | 中文（普通话、粤语、吴语、闽南语、客家话、赣语、湘语、晋语；并支持中原、西南、冀鲁、江淮、兰银、胶辽、东北、北京、港台等，包括河南、陕西、湖北、四川、重庆、云南、贵州、广东、广西、河北、天津、山东、安徽、南京、江苏、杭州、甘肃、宁夏等地区官话口音）、英文、日语 | 16kHz | 视频直播、会议、电话客服等 | pcm、wav、mp3、opus、speex、aac、amr | 0.00066元/秒 |
| fun-asr-realtime-2025-11-07 | 快照版 |

## **API参考**

### **连接端点 (URL)**

```
wss://dashscope.aliyuncs.com/api-ws/v1/inference
```

### **请求头 (Headers)**

| **参数** | **类型** | **是否必选** | **说明** |
| --- | --- | --- | --- |
| Authorization | string | 是   | 鉴权令牌，格式为`Bearer <your_api_key>`，使用时，将“`<your_api_key>`”替换为实际的API Key。 |
| user-agent | string | 否   | 客户端标识，便于服务端追踪来源。 |
| X-DashScope-WorkSpace | string | 否   | 阿里云百炼[业务空间ID](https://help.aliyun.com/zh/model-studio/use-workspace#c5222ec081sbo)。 |
| X-DashScope-DataInspection | string | 否   | 是否启用数据合规检测功能。默认不传或设为`enable`。如非必要，请勿启用该参数。 |

### **指令（客户端→服务端）**

指令是客户端发送的JSON格式文本消息，用于控制识别任务的生命周期。

#### **1\. run-task指令：开启任务**

**目的**：连接建立后，发送此指令以启动语音识别任务并配置相关参数。

**示例：**

```
{
    "header": {
        "action": "run-task",
        "task_id": "2bf83b9a-baeb-4fda-8d9a-xxxxxxxxxxxx",
        "streaming": "duplex"
    },
    "payload": {
        "task_group": "audio",
        "task": "asr",
        "function": "recognition",
        "model": "fun-asr-realtime",
        "parameters": {
            "format": "pcm",
            "sample_rate": 16000,
            "vocabulary_id": "vocab-xxx-24ee19fa8cfb4d52902170a0xxxxxxxx"
        },
        "input": {}
    }
}
```

`**header**`**参数说明：**

| **参数** | **类型** | **是否必选** | **说明** |
| --- | --- | --- | --- |
| header.action | string | 是   | 指令类型，固定为`run-task`。 |
| header.task\\_id | string | 是   | 任务的唯一标识。后续的[finish-task指令](#2e967d2d349es)需使用相同的`task_id`。 |
| header.streaming | string | 是   | 通信模式，固定为`duplex`。 |

`**payload**`**参数说明：**

| **参数** | **类型** | **是否必选** | **说明** |
| --- | --- | --- | --- |
| payload.task\\_group | string | 是   | 任务组，固定为`audio`。 |
| payload.task | string | 是   | 任务类型，固定为`asr`。 |
| payload.function | string | 是   | 功能类型，固定为`recognition`。 |
| payload.model | string | 是   | 指定要使用的模型。详情参见模型列表。 |
| payload.input | object | 是   | 输入配置，固定为空对象`{}`。 |
| **payload.parameters** |   |   |   |
| format | string | 是   | 音频格式。支持：`pcm`, `wav`, `mp3`, `opus`, `speex`, `aac`, `amr`。详细约束见[音频流规范](#4fad5a12ed137)。 |
| sample\\_rate | integer | 是   | 音频采样率（Hz）。 fun-asr-realtime支持16000Hz采样。 |
| vocabulary\\_id | string | 否   | 热词ID。使用方法参见[定制热词](https://help.aliyun.com/zh/model-studio/custom-hot-words)。 默认不设置。 |
| semantic\\_punctuation\\_enabled | boolean | 否   | 是否开启语义断句。 默认值：`false`。 - true：使用语义断句。关闭 VAD（Voice Activity Detection，语音活动检测）断句。适合会议转写，准确度高。 - false：使用 VAD 断句。关闭语义断句。适合交互场景，延迟低。 语义断句能更精准地识别句子边界。VAD 断句响应更快。通过调整 `semantic_punctuation_enabled` 参数，可在不同场景间灵活切换断句方式。 |
| max\\_sentence\\_silence | integer | 否   | VAD静音时长阈值。在 VAD（Voice Activity Detection，语音活动检测）断句中，静音时长超过该阈值即判定句子结束。 单位：毫秒（ms）。 默认值：1300。 取值范围：\\[200, 6000\\]。 生效条件：仅在 `semantic_punctuation_enabled` 参数为 `false`（使用 VAD 断句）时有效。 |
| multi\\_threshold\\_mode\\_enabled | boolean | 否   | 是否开启防止 VAD 断句过长的功能。 默认值：`false`。 - true：开启，限制 VAD（Voice Activity Detection，语音活动检测）断句长度，避免过长切割。 - false：关闭。 生效条件：仅在 `semantic_punctuation_enabled` 为 `false`（使用 VAD 断句）时有效。 |
| heartbeat | boolean | 否   | 是否开启长连接保持开关。 默认值：`false`。 - true：开启。在持续发送静音音频时，连接与服务端保持不中断。 - false：关闭。即使持续发送静音音频，60 秒后连接因超时断开。 说明： - 静音音频：音频文件或数据流中无声音信号的内容。 - 生成方式：可用音频编辑软件（如 Audacity、Adobe Audition），或命令行工具（如 FFmpeg）创建。 |
| language\\_hints | array\\[string\\] | 否   | 设置待识别语言代码。如果无法提前确定语种，可不设置，模型会自动识别语种。 不同模型支持的语言代码如下： - fun-asr-realtime、fun-asr-realtime-2025-11-07： - zh: 中文 - en: 英文 - ja: 日语 - fun-asr-realtime-2025-09-15： - zh: 中文 - en: 英文 |

#### **2\. finish-task指令：结束任务**

**目的**：客户端音频数据发送完毕后，发送此指令通知服务端。

**示例：**

```
{
    "header": {
        "action": "finish-task",
        "task_id": "2bf83b9a-baeb-4fda-8d9a-xxxxxxxxxxxx",
        "streaming": "duplex"
    },
    "payload": {
        "input": {}
    }
}
```

`**header**`**参数说明：**

| **参数** | **类型** | **是否必选** | **说明** |
| --- | --- | --- | --- |
| header.action | string | 是   | 指令类型，固定为`finish-task`。 |
| header.task\\_id | string | 是   | 任务ID，须与[run-task指令](#12d8a57443dmz)中的`task_id`一致。 |
| header.streaming | string | 是   | 通信模式，固定为`duplex`。 |

`**payload**`**参数说明：**

| **参数** | **类型** | **是否必选** | **说明** |
| --- | --- | --- | --- |
| payload.input | object | 是   | 输入配置，固定为空对象`{}`。 |

### **事件（服务端→客户端）**

事件是服务端发送的JSON格式文本消息，用于同步任务状态和识别结果。

#### **1\. task-started**

**触发时机**：服务端成功处理[run-task指令](#12d8a57443dmz)后。  
**作用**：通知客户端任务已开启，可开始发送音频数据。

**示例：**

```
{
    "header": {
        "task_id": "2bf83b9a-baeb-4fda-8d9a-xxxxxxxxxxxx",
        "event": "task-started",
        "attributes": {}
    },
    "payload": {}
}
```

`**header**`**参数说明：**

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| header.event | string | 事件类型，固定为`task-started`。 |
| header.task\\_id | string | 任务ID。 |

#### **2\. result-generated**

**触发时机**：识别过程中，服务端生成了新的识别结果时。  
**作用**：返回实时识别结果，包括中间结果和最终句结果。

**示例：**

```
{
  "header": {
    "task_id": "2bf83b9a-baeb-4fda-8d9a-xxxxxxxxxxxx",
    "event": "result-generated",
    "attributes": {}
  },
  "payload": {
    "output": {
      "sentence": {
        "begin_time": 170,
        "end_time": 920,
        "text": "好，我知道了",
        "heartbeat": false,
        "sentence_end": true,
        "words": [
          {
            "begin_time": 170,
            "end_time": 295,
            "text": "好",
            "punctuation": "，"
          },
          {
            "begin_time": 295,
            "end_time": 503,
            "text": "我",
            "punctuation": ""
          },
          {
            "begin_time": 503,
            "end_time": 711,
            "text": "知道",
            "punctuation": ""
          },
          {
            "begin_time": 711,
            "end_time": 920,
            "text": "了",
            "punctuation": ""
          }
        ]
      }
    },
    "usage": {
      "duration": 3
    }
  }
}
```

`**header**`**参数说明：**

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| header.event | string | 事件类型，固定为`result-generated`。 |
| header.task\\_id | string | 任务ID。 |

`**payload**`**参数说明：**

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| output | object | output.sentence为识别结果，详细内容见下文。 |
| usage | object | 当`payload.output.sentence.sentence_end`为`false`（当前句子未结束，参见[payload.output.sentence参数说明](#7114eb777ac9a)）时，`usage`为`null`。 当`payload.output.sentence.sentence_end`为`true`（当前句子已结束，参见[payload.output.sentence参数说明](#7114eb777ac9a)）时，`usage.duration`为当前任务计费时长（秒）。 |

`` `payload.usage`格式如下： ``

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| duration | integer | 任务计费时长（单位为秒）。 |

payload.output.sentence格式如下：

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| begin\\_time | integer | 句子开始时间，单位为ms。 |
| end\\_time | integer \\| null | 句子结束时间，单位为ms。如果为中间识别结果则为null。 |
| text | string | 识别出的文本内容。 |
| words | array | 字时间戳信息。 |
| heartbeat | boolean \\| null | 若该值为true，可跳过识别结果的处理。该值和[run-task指令](#12d8a57443dmz)中的heartbeat保持一致。 |
| sentence\\_end | boolean | 判断给定句子是否已结束。 |

`payload.output.sentence.words`为字时间戳列表，其中每一个word格式如下：

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| begin\\_time | integer | 字开始时间，单位为ms。 |
| end\\_time | integer | 字结束时间，单位为ms。 |
| text | string | 识别出的字。 |
| punctuation | string | 标点。 |

#### **3\. task-finished**

**触发时机**：服务端收到[finish-task指令](#2e967d2d349es)并处理完所有缓存的音频后。  
**作用**：标志识别任务成功结束。

**示例：**

```
{
    "header": {
        "task_id": "2bf83b9a-baeb-4fda-8d9a-xxxxxxxxxxxx",
        "event": "task-finished",
        "attributes": {}
    },
    "payload": {
        "output": {}
    }
}
```

`**header**`**参数说明：**

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| header.event | string | 事件类型，固定为`task-finished`。 |
| header.task\\_id | string | 任务ID。 |

#### **4\. task-failed**

**触发时机**：任务处理过程中发生任何错误时。  
**作用**：通知客户端任务失败并提供错误原因。收到此事件后，需要关闭WebSocket连接并处理错误。

**示例：**

```
{
    "header": {
        "task_id": "2bf83b9a-baeb-4fda-8d9a-xxxxxxxxxxxx",
        "event": "task-failed",
        "error_code": "CLIENT_ERROR",
        "error_message": "request timeout after 23 seconds.",
        "attributes": {}
    },
    "payload": {}
}
```

`**header**`**参数说明：**

| **参数** | **类型** | **说明** |
| --- | --- | --- |
| header.event | string | 事件类型，固定为`task-failed`。 |
| header.task\\_id | string | 任务ID。 |
| header.error\\_code | string | 报错类型描述。 |
| header.error\\_message | string | 具体报错原因。 |

## **关于建连开销和连接复用**

WebSocket服务支持连接复用以提升资源的利用效率，避免建立连接开销。

服务端收到客户端发送的[run-task指令](#12d8a57443dmz)后，将启动一个新的任务，客户端发送[finish-task指令](#2e967d2d349es)后，服务端在任务完成时返回[task-finished事件](#f11a341732xug)以结束该任务。结束任务后WebSocket连接可以被复用，客户端重新发送[run-task指令](#12d8a57443dmz)即可开启下一个任务。

**重要**

1.  在复用连接中的不同任务需要使用不同 task\_id。
    
2.  如果在任务执行过程中发生失败，服务将返回[task-failed事件](#ea4609132a8u7)，并关闭该连接。此时这个连接无法继续复用。
    
3.  如果在任务结束后60秒没有新的任务，连接会超时自动断开。
    

## **错误码**

如遇报错问题，请参见[错误信息](https://help.aliyun.com/zh/model-studio/error-code)进行排查。

## **常见问题**

### **功能特性**

#### **Q：在长时间静默的情况下，如何保持与服务端长连接？**

将请求参数`heartbeat`设置为true，并持续向服务端发送静音音频。

说明：

-   静音音频：音频文件或数据流中无声音信号的内容。
    
-   生成方式：可用音频编辑软件（如 Audacity、Adobe Audition），或命令行工具（如 FFmpeg）创建。
    

#### **Q：如何将音频格式转换为满足要求的格式？**

可使用[FFmpeg工具](https://ffmpeg.en.lo4d.com/download)，更多用法请参见FFmpeg官网。

```
# 基础转换命令（万能模板）
# -i，作用：输入文件路径，常用值示例：audio.wav
# -c:a，作用：音频编码器，常用值示例：aac, libmp3lame, pcm_s16le
# -b:a，作用：比特率（音质控制），常用值示例：192k, 320k
# -ar，作用：采样率
# -ac，作用：声道数，常用值示例：1(单声道), 2(立体声)
# -y，作用：覆盖已存在文件(无需值)
ffmpeg -i input_audio.ext -c:a 编码器名 -b:a 比特率 -ar 采样率 -ac 声道数 output.ext

# 例如：WAV → MP3（保持原始质量）
ffmpeg -i input.wav -c:a libmp3lame -q:a 0 output.mp3
# 例如：MP3 → WAV（16bit PCM标准格式）
ffmpeg -i input.mp3 -c:a pcm_s16le -ar 16000 -ac 2 output.wav
# 例如：M4A → AAC（提取/转换苹果音频）
ffmpeg -i input.m4a -c:a copy output.aac  # 直接提取不重编码
ffmpeg -i input.m4a -c:a aac -b:a 256k output.aac  # 重编码提高质量
# 例如：FLAC无损 → Opus（高压缩）
ffmpeg -i input.flac -c:a libopus -b:a 128k -vbr on output.opus
```

#### **Q：为什么使用WebSocket协议而非HTTP/HTTPS协议？为什么不提供RESTful API？**

语音服务选择 WebSocket 而非 HTTP/HTTPS/RESTful，根本在于其依赖全双工通信能力——WebSocket 允许服务端与客户端主动双向传输数据（如实时推送语音合成/识别进度），而基于 HTTP 的 RESTful 仅支持客户端发起的单向请求-响应模式，无法满足实时交互需求。

### **故障排查**

如遇代码报错问题，请根据[错误码](https://help.aliyun.com/zh/model-studio/websocket-for-paraformer-real-time-service#605d5ca873bnd)中的信息进行排查。

#### **Q：无法识别语音（无识别结果）是什么原因？**

1.  请检查请求参数中的音频格式（`format`）和采样率（`sample_rate`）设置是否正确且符合参数约束。以下为常见错误示例：
    
    -   音频文件扩展名为 .wav，但实际为 MP3 格式，而请求参数 `format` 设置为 mp3（参数设置错误）。
        
    -   音频采样率为 3600Hz，但请求参数 `sample_rate` 设置为 48000（参数设置错误）。
        
    
    可以使用[ffprobe](https://ffmpeg.org/ffprobe.html)工具获取音频的容器、编码、采样率、声道等信息：
    
    ```
    ffprobe -v error -show_entries format=format_name -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 input.xxx
    ```
    
2.  若以上检查无问题，可通过定制热词提升对特定词语的识别效果。