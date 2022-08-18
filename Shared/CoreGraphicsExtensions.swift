import CoreGraphics
import Metal

// https://eugenebokhan.io/introduction-to-metal-compute-part-four
func makeCGImage(texture: MTLTexture) -> CGImage? {
    let bytesPerRow = texture.width * 4
    let length = bytesPerRow * texture.height

    let rgbaBytes = UnsafeMutableRawPointer.allocate(
        byteCount: length,
        alignment: MemoryLayout<UInt8>.alignment
    )
    defer {
        rgbaBytes.deallocate()
    }

    let destinationRegion = MTLRegion(
        origin: .init(x: 0, y: 0, z: 0),
        size: .init(
            width: texture.width,
            height: texture.height,
            depth: texture.depth
        )
    )
    texture.getBytes(
        rgbaBytes,
        bytesPerRow: bytesPerRow,
        from: destinationRegion,
        
        mipmapLevel: 0
    )

    let colorScape = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageByteOrderInfo.order32Little
    let alphaInfo = CGImageAlphaInfo.premultipliedFirst

    let data = CFDataCreate(
        nil,
        rgbaBytes.assumingMemoryBound(to: UInt8.self),
        length
    )
    
    let dataProvider = data.flatMap { data in
        CGDataProvider(data: data)
    }

    let image = dataProvider.flatMap { dataProvider in
        CGImage(
            width: texture.width,
            height: texture.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorScape,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo.rawValue | alphaInfo.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
    
    return image
}
