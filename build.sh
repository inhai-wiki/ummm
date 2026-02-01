#!/bin/bash

# Ummm 语音输入应用编译脚本 - Universal Binary

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Ummm"
BUNDLE_DIR="${SCRIPT_DIR}/${APP_NAME}.app"

echo "编译中 (Universal Binary)..."

cd "${SCRIPT_DIR}/Ummm"

# 编译 arm64 版本
swiftc -parse-as-library \
    -target arm64-apple-macosx12.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework SwiftUI \
    -framework Speech \
    -framework AVFoundation \
    -framework AppKit \
    -framework Carbon \
    -o "../UmmmBin_arm64" \
    UmmmApp.swift \
    ContentView.swift \
    SpeechRecognizer.swift \
    HotkeyManager.swift \
    AliyunASR.swift

# 编译 x86_64 版本
swiftc -parse-as-library \
    -target x86_64-apple-macosx12.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -framework SwiftUI \
    -framework Speech \
    -framework AVFoundation \
    -framework AppKit \
    -framework Carbon \
    -o "../UmmmBin_x86_64" \
    UmmmApp.swift \
    ContentView.swift \
    SpeechRecognizer.swift \
    HotkeyManager.swift \
    AliyunASR.swift

# 合并为 Universal Binary
lipo -create -output "../UmmmBin" "../UmmmBin_arm64" "../UmmmBin_x86_64"
rm -f "../UmmmBin_arm64" "../UmmmBin_x86_64"

echo "编译成功 (arm64 + x86_64)"

# 创建应用包结构
echo "创建应用包..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# 复制文件
cp "../UmmmBin" "${BUNDLE_DIR}/Contents/MacOS/Ummm"
cp "Info.plist" "${BUNDLE_DIR}/Contents/"
cp "../Ummm.icns" "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
echo "APPL????" > "${BUNDLE_DIR}/Contents/PkgInfo"

echo "应用包创建成功: ${BUNDLE_DIR}"

# 代码签名（保持权限一致性）
echo "代码签名中..."
codesign --force --deep --sign - "${BUNDLE_DIR}"
echo "签名完成"

echo "运行: open ${BUNDLE_DIR}"
