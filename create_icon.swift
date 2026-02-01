import AppKit
import Foundation

// 创建 Ummm Logo - 简洁黑底白色声波条
func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    
    image.lockFocus()
    
    // 透明背景
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    
    // 图标内容区域（留出 10% 边距）
    let padding = size * 0.1
    let contentSize = size - padding * 2
    let offsetX = padding
    let offsetY = padding
    
    // 纯黑色背景
    let bgColor = NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1.0)
    
    // 圆角背景
    let bgPath = NSBezierPath(roundedRect: NSRect(x: offsetX, y: offsetY, width: contentSize, height: contentSize), 
                              xRadius: contentSize * 0.22, yRadius: contentSize * 0.22)
    bgColor.setFill()
    bgPath.fill()
    
    // 绘制三个声波条
    let barWidth = contentSize * 0.1
    let spacing = contentSize * 0.16
    let centerX = offsetX + contentSize / 2
    let centerY = offsetY + contentSize / 2
    
    // 中间高，两边低
    let heights: [CGFloat] = [0.22, 0.42, 0.22]
    
    NSColor.white.setFill()
    
    for (index, height) in heights.enumerated() {
        let barHeight = contentSize * height
        let x = centerX + CGFloat(index - 1) * spacing - barWidth / 2
        let y = centerY - barHeight / 2
        
        let barPath = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight),
                                   xRadius: barWidth / 2, yRadius: barWidth / 2)
        barPath.fill()
    }
    
    image.unlockFocus()
    return image
}

// 生成不同尺寸的图标
let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x")
]

// 创建 iconset 目录
let iconsetPath = "/Users/inhai/Desktop/apple_asr_test/Ummm.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let icon = createIcon(size: size)
    if let tiffData = icon.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let filePath = "\(iconsetPath)/\(name).png"
        try? pngData.write(to: URL(fileURLWithPath: filePath))
        print("Created: \(name).png")
    }
}

print("Icon set created!")
