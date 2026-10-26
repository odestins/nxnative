import SwiftUI
import ImageIO
import iSwitchCore

@MainActor private enum CoverCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 100
        return cache
    }()
}

enum CoverImageLoader {
    /// Decode only the pixels the largest card can display, away from the UI actor.
    static func load(_ url: URL) -> UIImage? {
        guard let data = try? boundedRead(url, maximum: 512 * 1024),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 768
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

struct CoverArt: View {
    let game: LibraryGame
    let directory: URL
    var preview = false
    @State private var image: UIImage?
    private var artworkURL: URL? { game.artworkFilename.map { directory.appendingPathComponent($0) } }

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if preview { SampleCover(index: Int(game.id.suffix(1)) ?? 1, title: game.manifest.name) }
            else {
                LinearGradient(colors: [Color(red: 0.13, green: 0.30, blue: 0.37), Color(red: 0.08, green: 0.14, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 18) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 48, weight: .light)).foregroundStyle(Palette.accent.opacity(0.8))
                    Text(game.manifest.name).font(.system(.title3, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center).foregroundStyle(.white).lineLimit(3).minimumScaleFactor(0.7)
                }.padding(24)
            }
        }
        .clipped()
        .task(id: artworkURL) {
            image = nil
            guard let url = artworkURL else { return }
            let key = url.standardizedFileURL.path as NSString
            if let cached = CoverCache.images.object(forKey: key) { image = cached; return }
            let decoded = await Task.detached(priority: .userInitiated) { CoverImageLoader.load(url) }.value
            guard !Task.isCancelled, let decoded, let pixels = decoded.cgImage else { return }
            CoverCache.images.setObject(decoded, forKey: key, cost: pixels.bytesPerRow * pixels.height)
            image = decoded
        }
        .accessibilityHidden(true)
    }
}

/// Original procedural artwork used only in the explicitly labeled layout preview.
struct SampleCover: View {
    let index: Int
    let title: String
    var colors: [Color] {
        switch index {
        case 1: [Color(red: 0.06, green: 0.31, blue: 0.44), Color(red: 0.62, green: 0.80, blue: 0.69)]
        case 2: [Color(red: 0.16, green: 0.11, blue: 0.42), Color(red: 0.65, green: 0.27, blue: 0.46)]
        case 3: [Color(red: 0.13, green: 0.31, blue: 0.24), Color(red: 0.73, green: 0.79, blue: 0.51)]
        case 4: [Color(red: 0.08, green: 0.07, blue: 0.29), Color(red: 0.59, green: 0.14, blue: 0.49)]
        default: [Color(red: 0.06, green: 0.32, blue: 0.42), Color(red: 0.25, green: 0.72, blue: 0.69)]
        }
    }
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    let w = size.width, h = size.height
                    let sun = CGRect(x: w * 0.57, y: h * 0.16, width: w * 0.27, height: w * 0.27)
                    context.fill(Path(ellipseIn: sun), with: .color(Color(red: 1, green: 0.88, blue: 0.64)))
                    for layer in 0..<4 {
                        let offset = CGFloat(layer) * 0.13
                        var path = Path()
                        path.move(to: CGPoint(x: -w * 0.1, y: h * (0.68 + offset)))
                        path.addLine(to: CGPoint(x: w * 0.22, y: h * (0.27 + offset)))
                        path.addLine(to: CGPoint(x: w * 0.39, y: h * (0.51 + offset)))
                        path.addLine(to: CGPoint(x: w * 0.64, y: h * (0.39 + offset)))
                        path.addLine(to: CGPoint(x: w * 1.1, y: h * (0.67 + offset)))
                        path.addLine(to: CGPoint(x: w * 1.1, y: h))
                        path.addLine(to: CGPoint(x: -w * 0.1, y: h)); path.closeSubpath()
                        context.fill(path, with: .color(colors[0].opacity(0.30 + Double(layer) * 0.18)))
                    }
                    if index == 2 || index == 4 {
                        for line in 0..<7 {
                            var path = Path()
                            path.move(to: CGPoint(x: w * (CGFloat(line) * 0.18 - 0.2), y: h))
                            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.43))
                            context.stroke(path, with: .color(Palette.coral.opacity(0.65)), lineWidth: 2)
                        }
                    }
                    for dot in 0..<18 {
                        let x = CGFloat((dot * 47 + index * 31) % 100) / 100 * w
                        let y = CGFloat((dot * 23 + 3) % 40) / 100 * h
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.5)))
                    }
                }
                VStack(spacing: 5) {
                    Text("re S W I T C H   O R I G I N A L S").font(.system(size: max(6, g.size.width * 0.023), weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(title).font(.system(size: g.size.width * (index == 1 ? 0.15 : 0.12), weight: .black, design: .rounded))
                        .tracking(index == 1 ? 4 : -0.8).multilineTextAlignment(.center).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    Text(index == 1 ? "A WORLD ABOVE" : index == 2 ? "BEYOND THE FINISH LINE" : index == 3 ? "A LITTLE ROOM TO GROW" : "FIND YOUR HORIZON")
                        .font(.system(size: max(6, g.size.width * 0.026), weight: .semibold)).tracking(2)
                        .foregroundStyle(.white.opacity(0.75))
                }.padding(g.size.width * 0.09).padding(.bottom, g.size.height * 0.035)
            }
        }
    }
}
