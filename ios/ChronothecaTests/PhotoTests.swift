import XCTest
import ImageIO
import UIKit
@testable import Chronotheca

/// Снимки ложатся в формате, в котором их снял iPhone, и сжимаются одним
/// средним сжатием (P365, P633).
final class PhotoTests: XCTestCase {

    private func jpeg(_ w: CGFloat, _ h: CGFloat) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h),
                                            format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { ctx in
                UIColor.systemTeal.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func width(_ data: Data) -> Int {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return props[kCGImagePropertyPixelWidth] as! Int
    }

    func testСжатиеУменьшаетИФорматНеМеняет() {
        let strong = Photo.stored(from: jpeg(3000, 2000))
        XCTAssertEqual(strong?.ext, "jpg", "JPEG остаётся JPEG")
        XCTAssertEqual(strong.map { width($0.data) }, 2560)
        // Меньший снимок не растягивается.
        XCTAssertEqual(Photo.stored(from: jpeg(1200, 900)).map { width($0.data) }, 1200)
    }
}
