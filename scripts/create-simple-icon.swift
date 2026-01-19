#!/usr/bin/env swift
import AppKit
import Foundation

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let context = NSGraphicsContext.current!.cgContext
    
    // Create gradient background (sunset theme matching the app)
    let colors = [
        CGColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0), // Orange
        CGColor(red: 0.3, green: 0.4, blue: 0.8, alpha: 1.0)  // Indigo
    ]
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0])!
    
    context.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: size),
                              end: CGPoint(x: 0, y: 0),
                              options: [])
    
    // Draw sun circle in center
    let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    let radius = CGFloat(size) / 3
    
    context.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
    
    // Draw sun rays
    context.setStrokeColor(CGColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1.0))
    context.setLineWidth(CGFloat(size) / 40)
    
    for i in 0..<8 {
        let angle = Double(i) * .pi / 4
        let startRadius = radius + CGFloat(size) / 20
        let endRadius = radius + CGFloat(size) / 8
        
        let startX = center.x + cos(angle) * startRadius
        let startY = center.y + sin(angle) * startRadius
        let endX = center.x + cos(angle) * endRadius
        let endY = center.y + sin(angle) * endRadius
        
        context.move(to: CGPoint(x: startX, y: startY))
        context.addLine(to: CGPoint(x: endX, y: endY))
        context.strokePath()
    }
    
    return true
}

// Save as PNG
let tiffData = image.tiffRepresentation!
let bitmapImage = NSBitmapImageRep(data: tiffData)!
let pngData = bitmapImage.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!

let outputPath = "assets/icon.png"
try? FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try! pngData.write(to: URL(fileURLWithPath: outputPath))

print("Created \(outputPath)")
