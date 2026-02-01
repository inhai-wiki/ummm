#!/bin/bash

# DMG 打包脚本 - 带 Applications 快捷方式

APP_NAME="Ummm"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
SOURCE_DIR="/Users/inhai/Desktop/apple_asr_test"
TEMP_DMG="${SOURCE_DIR}/temp_${DMG_NAME}"

echo "Creating DMG with Applications shortcut..."

# 删除旧文件
rm -f "${SOURCE_DIR}/${DMG_NAME}"
rm -f "${TEMP_DMG}"

# 创建临时文件夹
STAGING_DIR="${SOURCE_DIR}/dmg_staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# 复制应用
cp -R "${SOURCE_DIR}/${APP_NAME}.app" "${STAGING_DIR}/"

# 创建 Applications 快捷方式
ln -s /Applications "${STAGING_DIR}/Applications"

# 创建可写 DMG
hdiutil create -srcfolder "${STAGING_DIR}" -volname "${VOLUME_NAME}" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "${TEMP_DMG}"

# 挂载 DMG
DEVICE=$(hdiutil attach -readwrite -noverify "${TEMP_DMG}" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/${VOLUME_NAME}"

sleep 2

# 设置窗口样式
echo '
   tell application "Finder"
     tell disk "'${VOLUME_NAME}'"
           open
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           set the bounds of container window to {400, 100, 920, 440}
           set viewOptions to the icon view options of container window
           set arrangement of viewOptions to not arranged
           set icon size of viewOptions to 80
           set position of item "'${APP_NAME}'.app" of container window to {130, 180}
           set position of item "Applications" of container window to {390, 180}
           close
           open
           update without registering applications
           delay 2
     end tell
   end tell
' | osascript

sync

# 卸载
hdiutil detach "${DEVICE}"

# 转换为压缩格式
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${SOURCE_DIR}/${DMG_NAME}"

# 清理
rm -f "${TEMP_DMG}"
rm -rf "${STAGING_DIR}"

echo "DMG created: ${SOURCE_DIR}/${DMG_NAME}"
