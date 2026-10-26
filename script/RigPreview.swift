import AppKit
import SwiftUI

@main struct RigPreview {
    @MainActor static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for style in PetFullBodyStyle.allCases {
            guard let assets = PetRigAssets(resources: base, style: style) else { fatalError("Missing atlas") }
            let poses = [PetRigPose(),
                         PetRigMotion.sample(time: 101.4, idle: false, reaction: PetReactionSession(kind: .wave, startedAt: 100)),
                         PetRigMotion.sample(time: 101.4, idle: false, reaction: PetReactionSession(kind: .pet, startedAt: 100)),
                         PetRigMotion.sample(time: 101.4, idle: false, dragging: true, dragAge: 1, dragSway: 0.7)]
            let content = HStack(spacing: 12) {
                ForEach(poses.indices, id: \.self) { index in
                    PetRigView(assets: assets, pose: poses[index]).frame(width: 208, height: 320)
                }
            }.padding(20).background(Color(red: 0.91, green: 0.90, blue: 0.95))
            let renderer = ImageRenderer(content: content); renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Render failed") }
            try data.write(to: output.appendingPathComponent("rig-\(style.rawValue)-preview.png"))
            print("Rendered \(style.rawValue): \(assets.images.count) cached parts")
        }
    }
}
