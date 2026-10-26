import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO
import iSwitchCore

/// Photos grants access to only the selected image. Keep a bounded temporary file
/// while ImageIO downsamples, instead of decoding a full-resolution photo on the UI actor.
struct SelectedProfilePhoto: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 100 * 1024 * 1024 else { throw LibraryError.invalid("Choose a photo smaller than 100 MB.") }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return SelectedProfilePhoto(url: destination)
        }
    }
}

actor ProfilePhotoStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("profile.jpg") }
    init(directory: URL) { self.directory = directory }

    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try boundedRead(file, maximum: 256 * 1024)
    }

    func save(_ sourceURL: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 30_000, height <= 30_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
            throw LibraryError.invalid("This photo could not be opened. Choose another image.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw LibraryError.invalid("The photo could not be saved.") }
        // Re-encoding also strips the original photo's location and camera metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 256 * 1024 else { throw LibraryError.invalid("The photo could not be resized. Choose another image.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (data as Data).write(to: file, options: [.atomic, .completeFileProtection])
        return data as Data
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
