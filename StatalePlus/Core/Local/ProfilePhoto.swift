import UIKit
import Observation

/// Foto profilo locale (Application Support/profilo.jpg), ridimensionata a 600 px sul lato lungo.
@Observable
final class ProfilePhoto {
    private(set) var image: UIImage?
    private let url = URL.applicationSupportDirectory.appending(path: "profilo.jpg")

    init() {
        image = UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    func set(_ data: Data) {
        guard let original = UIImage(data: data) else { return }
        let scale = min(1, 600 / max(original.size.width, original.size.height))
        let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        image = resized
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
        image = nil
    }
}
