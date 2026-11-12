#!/usr/bin/env swift
// Draws the SwitchDeck app icon and writes Resources/AppIcon.icns.
// Run from the repository root: `swift scripts/make-icon.swift`.
import AppKit

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))

canvas.lockFocus()

// Rounded square with a blue-to-violet gradient.
let plate = NSRect(x: 52, y: 52, width: size - 104, height: size - 104)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.31, green: 0.47, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.45, green: 0.24, blue: 0.92, alpha: 1),
])!
gradient.draw(in: platePath, angle: -90)

// Toggle track.
let track = NSRect(x: 212, y: 372, width: 600, height: 280)
let trackPath = NSBezierPath(roundedRect: track, xRadius: 140, yRadius: 140)
NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
trackPath.fill()
NSColor(calibratedWhite: 1, alpha: 0.55).setStroke()
trackPath.lineWidth = 10
trackPath.stroke()

// Knob on the right of the track.
let knobDiameter: CGFloat = 212
let knob = NSRect(
    x: track.maxX - knobDiameter - 34,
    y: track.midY - knobDiameter / 2,
    width: knobDiameter,
    height: knobDiameter
)
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()

NSColor.white.setFill()
NSBezierPath(ovalIn: knob).fill()

canvas.unlockFocus()

// Write the master and every iconset size.
let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = repo.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let masterURL = repo.appendingPathComponent("build/AppIcon-1024.png")
let tiff = canvas.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: masterURL)

let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in variants {
    let destination = iconset.appendingPathComponent("\(name).png")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(pixels)", "\(pixels)", masterURL.path, "--out", destination.path]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try! task.run()
    task.waitUntilExit()
}

let output = repo.appendingPathComponent("Resources/AppIcon.icns")
try! FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()

print("Wrote \(output.path)")
