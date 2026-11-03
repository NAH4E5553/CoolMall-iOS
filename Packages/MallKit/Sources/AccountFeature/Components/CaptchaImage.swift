import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Decodes only bounded challenge bytes supplied by the data capability.
/// No URL/network/storage access. Decode failure stays visible and refreshable.
struct CaptchaImage: View {
    let data: Data
    var body: some View {
        Group {
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 480,
                    ] as CFDictionary)
            {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Label("图片加载失败，点击重试", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .frame(width: 120, height: 52)
    }
}
