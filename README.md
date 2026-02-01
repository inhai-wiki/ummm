# Ummm
<img width="2940" height="1604" alt="image" src="https://github.com/user-attachments/assets/e9ad1fca-90f9-406e-9852-012b492ab513" />

macOS 语音转文字工具，按住说话，松开输入，比打字快 3 倍。

**在线页面**: https://ummm-landing.vercel.app/

**Landing Page 源码**: https://github.com/inhai-wiki/ummm-landing

**下载安装包**: https://inhai-wiki.oss-cn-hangzhou.aliyuncs.com/ummm/Ummm.dmg

---

## 项目介绍

Ummm 是一款 macOS 菜单栏应用，让语音输入变得简单自然：

- 按住 fn 键说话，松开即输入
- 文字自动出现在光标位置，无缝融入任何应用
- 支持本地识别（隐私优先）和阿里云 FunASR 云端识别（精准优先）

### 核心能力

| 能力 | 说明 |
|------|------|
| 实时转写 | 边说边转，即时看到结果 |
| 语气词过滤 | 自动去除"嗯""那个""就是"等语气词 |
| 领域热词 | 支持添加专业术语，提升识别准确率 |
| 中文优化 | 针对中文语音深度优化 |

---

## 系统要求

- macOS 12.0 Monterey 或更高版本
- Apple Silicon (M1/M2/M3) 或 Intel 芯片

---

## 项目结构

```
.
├── Ummm/                    # 源代码目录
│   ├── UmmmApp.swift        # 应用入口和主逻辑
│   ├── ContentView.swift    # UI 视图（浮动指示器、菜单栏）
│   ├── SpeechRecognizer.swift # 语音识别管理器
│   ├── HotkeyManager.swift  # 全局快捷键管理
│   ├── AliyunASR.swift      # 阿里云 FunASR 接入
│   ├── Info.plist           # 应用配置
│   └── Ummm.entitlements    # 权限声明
├── build.sh                 # 编译脚本（Universal Binary）
├── create_dmg.sh            # DMG 打包脚本
├── create_icon.swift        # 图标生成脚本
├── test_asr.swift           # ASR 测试脚本
└── asrapi.md                # 阿里云 ASR API 文档
```

---

## 技术架构

| 组件 | 技术 |
|------|------|
| 框架 | SwiftUI + AppKit |
| 本地识别 | Apple Speech Framework |
| 云端识别 | 阿里云 FunASR (WebSocket) |
| 快捷键 | Carbon Framework |
| 打包 | Universal Binary (arm64 + x86_64) |

---

## 编译运行

### 前置条件

- macOS 12.0+
- Xcode Command Line Tools

```bash
xcode-select --install
```

### 编译应用

```bash
# 编译 Universal Binary 并创建 .app 包
./build.sh
```

编译完成后，应用包位于 `Ummm.app`。

### 创建 DMG 安装包

```bash
./create_dmg.sh
```

### 运行应用

```bash
open Ummm.app
```

---

## 权限说明

应用需要以下系统权限：

| 权限 | 用途 | 设置路径 |
|------|------|---------|
| 麦克风 | 录制语音 | 系统设置 - 隐私与安全性 - 麦克风 |
| 辅助功能 | 监听快捷键 | 系统设置 - 隐私与安全性 - 辅助功能 |
| 语音识别 | 本地识别 | 系统设置 - 隐私与安全性 - 语音识别 |

---

## 云端识别配置

使用阿里云 FunASR 获得更精准的识别效果：

1. 访问阿里云百炼获取 API Key:
   https://bailian.console.aliyun.com/cn-beijing/?source_channel=%22ummm%22?tab=app#/api-key

2. 右键点击菜单栏图标，填入 API Key

3. 自动切换为云端识别引擎

### 领域热词微调

FunASR 支持添加专业术语，提升特定领域的识别准确率：

https://bailian.console.aliyun.com/cn-beijing/?source_channel=%22ummm%22/?tab=model#/efm/model_experience_center/voice

---

## 相关链接

| 资源 | 链接 |
|------|------|
| 在线页面 | https://ummm-landing.vercel.app/ |
| Landing Page 源码 | https://github.com/inhai-wiki/ummm-landing |
| 下载安装包 | https://inhai-wiki.oss-cn-hangzhou.aliyuncs.com/ummm/Ummm.dmg |
| 获取 API Key | https://bailian.console.aliyun.com/cn-beijing/?source_channel=%22ummm%22?tab=app#/api-key |
| 模型微调 | https://bailian.console.aliyun.com/cn-beijing/?source_channel=%22ummm%22/?tab=model#/efm/model_experience_center/voice |

---

## 许可证

MIT License

---

Powered by Qoder.ai & 阿里云百炼

Made by inhai - https://inhai.wiki
