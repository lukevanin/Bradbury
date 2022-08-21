import CoreGraphics
import Metal
import ImageIO

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


// See https://github.com/Hi-Rez/Satin/blob/70f576550ecb7a8df8f3121a6a1a4c8939e9c4d8/Source/Utilities/Textures.swift#L114
func loadHDR(device: MTLDevice, url: URL) -> MTLTexture? {
    
    let cfURLString = url.path as CFString
    guard let cfURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfURLString, CFURLPathStyle.cfurlposixPathStyle, false) else {
        fatalError("Failed to create CFURL from: \(url.path)")
    }
    guard let cgImageSource = CGImageSourceCreateWithURL(cfURL, nil) else {
        fatalError("Failed to create CGImageSource")
    }
    guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
        fatalError("Failed to create CGImage")
    }
    
    print(cgImage.width)
    print(cgImage.height)
    print(cgImage.bitsPerComponent)
    print(cgImage.bytesPerRow)
    print(cgImage.byteOrderInfo)
    
    guard let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order16Little.rawValue
    guard let bitmapContext = CGContext(
        data: nil,
        width: cgImage.width,
        height: cgImage.height,
        bitsPerComponent: cgImage.bitsPerComponent,
        bytesPerRow: cgImage.width * 2 * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo) else { return nil
    }
    
    bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    
    let descriptor = MTLTextureDescriptor()
    descriptor.pixelFormat = .rgba16Float
    descriptor.width = cgImage.width
    descriptor.height = cgImage.height
    descriptor.depth = 1
    descriptor.usage = .shaderRead
    descriptor.resourceOptions = .storageModeShared
    descriptor.sampleCount = 1
    descriptor.textureType = .type2D
    
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    texture.replace(
        region: MTLRegionMake2D(0, 0, cgImage.width, cgImage.height),
        mipmapLevel: 0,
        withBytes: bitmapContext.data!,
        bytesPerRow: cgImage.width * 2 * 4
    )
    
    return texture
}
