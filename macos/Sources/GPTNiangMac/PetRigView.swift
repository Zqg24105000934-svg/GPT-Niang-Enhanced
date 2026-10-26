import AppKit
import SwiftUI
#if canImport(GPTNiangCore)
import GPTNiangCore
#endif

enum PetRigPart: CaseIterable { case head, eyes, closedEyes, smile, body, leftArm, rightArm, hair, leftWing, rightWing, tail, leftLock, rightLock, leftLeg, rightLeg }

/// Crop once, cache only the selected atlas parts, and reuse the same textures.
/// Source coordinates are intentionally explicit: generated atlases need not
/// pretend to be an exactly regular sprite grid.
final class PetRigAssets {
    let style: PetFullBodyStyle
    let images: [PetRigPart: NSImage]
    init?(resources: URL, style: PetFullBodyStyle) {
        self.style = style
        let name = style == .winged ? "pet-rig-winged-v1.png" : "pet-rig-chibi-v1.png"
        guard let source = NSImage(contentsOf: resources.appendingPathComponent(name)),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width == 1448, cg.height == 1086 else { return nil }
        var result: [PetRigPart: NSImage] = [:]
        for (part, rect) in Self.rects(style) {
            guard let image = cg.cropping(to: rect) else { return nil }
            let extracted = [.eyes, .closedEyes, .smile].contains(part) ? image : Self.isolatedCutout(image)
            result[part] = NSImage(cgImage: extracted, size: rect.size)
        }
        if style == .chibi {
            guard let dress = NSImage(contentsOf: resources.appendingPathComponent("pet-rig-chibi-dress-v1.png")),
                  let full = dress.cgImage(forProposedRect:nil, context:nil, hints:nil),
                  full.width == 1320, full.height == 1192,
                  let cropped = full.cropping(to:CGRect(x:35,y:75,width:1250,height:1030)) else { return nil }
            let clean = Self.isolatedCutout(cropped)
            let width = 512, height = 422
            guard let resized = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            resized.interpolationQuality = .high
            resized.draw(clean,in:CGRect(x:0,y:0,width:width,height:height))
            guard let texture = resized.makeImage() else { return nil }
            result[.body] = NSImage(cgImage:texture,size:CGSize(width:width,height:height))
        }
        images = result
    }
    /// Atlas extraction rejects tiny disconnected fragments belonging to a
    /// neighboring cell. Eyes are deliberately exempt (brows are separate).
    /// This runs once at load, never in the animation loop; source art is kept.
    private static func isolatedCutout(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height, count = w * h
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags),
              let data = context.data else { return image }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var labels = [Int32](repeating: -1, count: count), sizes: [Int] = [], queue: [Int] = []
        queue.reserveCapacity(count)
        for start in 0..<count where labels[start] == -1 && pixels[start * 4 + 3] > 24 {
            let label = Int32(sizes.count)
            labels[start] = label; queue.removeAll(keepingCapacity: true); queue.append(start)
            var cursor = 0
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1
                let x = i % w, y = i / w
                for n in [x > 0 ? i - 1 : -1, x + 1 < w ? i + 1 : -1, y > 0 ? i - w : -1, y + 1 < h ? i + w : -1] {
                    if n >= 0 && labels[n] == -1 && pixels[n * 4 + 3] > 24 { labels[n] = label; queue.append(n) }
                }
            }
            sizes.append(queue.count)
        }
        let threshold = max(32, (sizes.max() ?? 0) / 140)
        var keep = [Bool](repeating: false, count: count)
        for i in 0..<count where labels[i] >= 0 { keep[i] = sizes[Int(labels[i])] >= threshold }
        for i in 0..<count where !keep[i] {
            let x = i % w, y = i / w
            // Retain the one-pixel translucent fringe of the selected cutout.
            let edge = pixels[i * 4 + 3] <= 24 &&
                ((x > 0 && keep[i-1]) || (x+1 < w && keep[i+1]) || (y > 0 && keep[i-w]) || (y+1 < h && keep[i+w]))
            if !edge { pixels[i*4] = 0; pixels[i*4+1] = 0; pixels[i*4+2] = 0; pixels[i*4+3] = 0 }
        }
        // The context owns the pixel buffer and snapshots it for the image.
        return context.makeImage() ?? image
    }
    private static func rects(_ style: PetFullBodyStyle) -> [PetRigPart: CGRect] {
        func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        if style == .winged {
            return [.head:r(44,0,390,328), .eyes:r(468,120,298,145), .closedEyes:r(824,120,298,145), .smile:r(1245,168,105,54),
                    .body:r(0,330,438,475), .leftArm:r(438,337,224,448), .rightArm:r(814,337,218,452),
                    .hair:r(1110,335,338,466), .leftWing:r(0,794,382,286), .rightWing:r(453,794,381,286),
                    .tail:r(834,789,270,292), .leftLock:r(1182,803,122,270), .rightLock:r(1308,803,109,270)]
        }
        return [.head:r(24,0,407,375), .eyes:r(445,130,315,170), .closedEyes:r(780,130,315,170), .smile:r(1218,208,90,88),
                .body:r(28,377,389,302), .leftArm:r(441,421,230,334), .rightArm:r(769,421,237,334),
                .hair:r(1025,350,423,461), .tail:r(739,804,343,280), .leftLock:r(1115,815,140,260), .rightLock:r(1261,815,158,260),
                .leftLeg:r(107,803,140,278), .rightLeg:r(474,799,145,282)]
    }
}

struct PetRigView: View {
    let assets: PetRigAssets
    var pose: PetRigPose
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            var c = context
            c.scaleBy(x: size.width / 208, y: size.height / 320)
            c.translateBy(x: 104, y: 307 + pose.bodyY)
            c.rotate(by: .degrees(pose.bodyAngle))
            c.scaleBy(x: 1, y: pose.bodyScaleY)
            c.translateBy(x: -104, y: -307)
            if assets.style == .winged { drawWinged(c) } else { drawChibi(c) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private func draw(_ part: PetRigPart, _ context: GraphicsContext, _ rect: CGRect,
                      angle: Double = 0, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5),
                      scaleX: Double = 1, scaleY: Double = 1, opacity: Double = 1) {
        guard opacity > 0.001, let source = assets.images[part] else { return }
        var c = context
        let pivot = CGPoint(x: rect.minX + rect.width * anchor.x, y: rect.minY + rect.height * anchor.y)
        c.translateBy(x: pivot.x, y: pivot.y); c.rotate(by: .degrees(angle))
        c.scaleBy(x: scaleX, y: scaleY); c.translateBy(x: -pivot.x, y: -pivot.y)
        c.opacity *= opacity
        if part == .leftWing {
            // The upper-left atlas corner contains a small neighboring hem
            // fragment, outside the wing's silhouette. Exclude only that corner.
            var silhouette = Path()
            silhouette.move(to:CGPoint(x:rect.minX,y:rect.minY + rect.height * 0.12))
            silhouette.addLine(to:CGPoint(x:rect.minX + rect.width * 0.72,y:rect.minY + rect.height * 0.12))
            silhouette.addLine(to:CGPoint(x:rect.minX + rect.width * 0.72,y:rect.minY))
            silhouette.addLine(to:CGPoint(x:rect.maxX,y:rect.minY)); silhouette.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
            silhouette.addLine(to:CGPoint(x:rect.minX,y:rect.maxY)); silhouette.closeSubpath()
            c.clip(to:silhouette)
        }
        c.draw(Image(nsImage: source), in: rect)
    }
    private func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x:x, y:y, width:w, height:h) }
    private func drawHead(_ context: GraphicsContext, rect: CGRect, eyeRect: CGRect, mouth: CGRect) {
        var h = context
        let x = rect.midX, y = rect.maxY - 4
        h.translateBy(x:x, y:y + pose.headY); h.rotate(by:.degrees(pose.headAngle)); h.translateBy(x:-x,y:-y)
        draw(.head, h, rect)
        let eyes = eyeRect.offsetBy(dx:pose.gazeX * (assets.style == .chibi ? 1.8 : 0.8), dy:pose.gazeY * 0.7)
        draw(.eyes, h, eyes, scaleY:0.18 + 0.82 * pose.eyesOpen, opacity:pose.eyesOpen)
        draw(.closedEyes, h, eyeRect, opacity:1 - pose.eyesOpen)
        draw(.smile, h, mouth, scaleY:0.65 + 0.35 * pose.smile, opacity:pose.smile)
    }
    private func drawWinged(_ c: GraphicsContext) {
        draw(.tail,c,r(121,165,73,121),angle:pose.tailAngle,anchor:CGPoint(x:0.10,y:0.08))
        draw(.leftWing,c,r(2,41,90,85),angle:pose.wingAngle,anchor:CGPoint(x:0.96,y:0.57),scaleX:pose.wingScale)
        draw(.rightWing,c,r(116,41,90,85),angle:-pose.wingAngle,anchor:CGPoint(x:0.04,y:0.57),scaleX:pose.wingScale)
        draw(.hair,c,r(63,17,85,140),angle:pose.hairAngle,anchor:CGPoint(x:0.5,y:0.10))
        draw(.leftArm,c,r(52,70,42,102),angle:pose.leftArm,anchor:CGPoint(x:0.79,y:0.05))
        draw(.rightArm,c,r(115,70,42,102),angle:pose.rightArm,anchor:CGPoint(x:0.16,y:0.05))
        var skirt = c
        skirt.clip(to:Path(CGRect(x:0,y:137,width:208,height:183)))
        draw(.body,skirt,r(22,60,164,248),angle:pose.dressAngle,anchor:CGPoint(x:0.5,y:0.315))
        var bodice = c
        bodice.clip(to:Path(CGRect(x:0,y:0,width:208,height:139)))
        draw(.body,bodice,r(22,60,164,248))
        drawHead(c,rect:r(65,5,78,64),eyeRect:r(85,42,37,18),mouth:r(101,56,6,3.8))
        draw(.leftLock,c,r(74,49,13,80),angle:pose.fringeAngle,anchor:CGPoint(x:0.65,y:0.04))
        draw(.rightLock,c,r(121,49,13,80),angle:-pose.fringeAngle,anchor:CGPoint(x:0.35,y:0.04))
    }
    private func drawChibi(_ c: GraphicsContext) {
        draw(.tail,c,r(119,226,82,74),angle:pose.tailAngle,anchor:CGPoint(x:0.13,y:0.10))
        draw(.hair,c,r(37,50,136,167),angle:pose.hairAngle,anchor:CGPoint(x:0.5,y:0.10))
        draw(.leftLeg,c,r(75,211,31,96),angle:pose.leftLeg,anchor:CGPoint(x:0.50,y:0.10))
        draw(.rightLeg,c,r(104,211,31,96),angle:pose.rightLeg,anchor:CGPoint(x:0.50,y:0.10))
        draw(.leftArm,c,r(42,150,49,96),angle:pose.leftArm,anchor:CGPoint(x:0.82,y:0.08))
        draw(.rightArm,c,r(117,150,49,96),angle:pose.rightArm,anchor:CGPoint(x:0.18,y:0.08))
        draw(.body,c,r(48,138,112,108),angle:pose.dressAngle * 0.5,anchor:CGPoint(x:0.5,y:0.05))
        drawHead(c,rect:r(35,8,138,138),eyeRect:r(67,82,74,40),mouth:r(101,117,6,6))
        draw(.leftLock,c,r(49,116,18,68),angle:pose.fringeAngle,anchor:CGPoint(x:0.6,y:0.05))
        draw(.rightLock,c,r(140,116,18,68),angle:-pose.fringeAngle,anchor:CGPoint(x:0.4,y:0.05))
    }
}
