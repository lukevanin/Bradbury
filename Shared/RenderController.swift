import Foundation
import CoreGraphics
import MetalKit


private func generateRandomData(_ buffer: MTLBuffer) {
    let count = buffer.length / MemoryLayout<Float>.size
    let rawPointer = buffer.contents().assumingMemoryBound(to: Float.self)
    for i in 0 ..< count {
        rawPointer[i] = Float.random(in: 0 ..< 1)
    }
}


final class MetalRenderer {
    
    typealias Completion = (CGImage) -> Void
    
    var completion: Completion?
    
    private let width: Int
    private let height: Int
    private let device: MTLDevice
    private let library: MTLLibrary
    private let function: MTLFunction
    private let computePipelineState: MTLComputePipelineState
    private let commandQueue: MTLCommandQueue
//    private let bufferA: MTLBuffer
//    private let bufferB: MTLBuffer
//    private let bufferResult: MTLBuffer
    private let inputTexture: MTLTexture
    private let outputTexture: MTLTexture
    
    init(width: Int, height: Int, device: MTLDevice) {
        self.width = width
        self.height = height
        self.device = device
        self.library = device.makeDefaultLibrary()!
        self.function = library.makeFunction(name: "render")!
        self.computePipelineState = try! device.makeComputePipelineState(function: function)
        self.commandQueue = device.makeCommandQueue()!
        
        self.inputTexture = device.makeTexture(
            descriptor: {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = .shaderRead
                return descriptor
            }()
        )!
        self.outputTexture = device.makeTexture(
            descriptor: {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = .shaderWrite
                return descriptor
            }()
        )!
        // TODO: Use cpu write combined mode for write-only buffers
//        self.bufferSize = MemoryLayout<Float>.size * 1_000_000
//        self.bufferA = device.makeBuffer(length: bufferSize, options: [.storageModeShared])!
//        self.bufferB = device.makeBuffer(length: bufferSize, options: [.storageModeShared])!
//        self.bufferResult = device.makeBuffer(length: bufferSize, options: [.storageModeShared])!
    }
    
//    func prepare() {
//        generateRandomData(bufferA)
//        generateRandomData(bufferB)
//    }
    
    func render() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            switch commandBuffer.status {
            case .committed:
                print("comitted")
            case .notEnqueued:
                print("not enqueued")
            case .enqueued:
                print("enqueued")
            case .scheduled:
                print("scheduled")
            case .completed:
                let duration = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                print("completed \(String(format: "%0.12f", duration)) seconds")
                self?.outputImage()
            case .error:
                print("error")
            @unknown default:
                print("unknown")
            }
        }

        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        let gridSize = MTLSize(
            width: width,
            height: height,
            depth: 1
        )
        let threadGroupSize = MTLSize(
            width: computePipelineState.threadExecutionWidth,
            height: computePipelineState.maxTotalThreadsPerThreadgroup / computePipelineState.threadExecutionWidth,
            depth: 1
        )
//        let threadGroupCount = MTLSize(
//            width: (gridSize.width + threadGroupSize.width - 1) / threadGroupSize.width,
//            height: (gridSize.height + threadGroupSize.height - 1) / threadGroupSize.height,
//            depth: 1
//        )
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
//        computeEncoder.dispatchThreads(threadGroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
    private func outputImage() {
        guard let image = makeCGImage(texture: outputTexture) else {
            return
        }
        completion?(image)
    }
    
//    private func verifyResults() {
//        let count = bufferResult.length / MemoryLayout<Float>.size
//        let a = bufferA.contents().assumingMemoryBound(to: Float.self)
//        let b = bufferB.contents().assumingMemoryBound(to: Float.self)
//        let r = bufferResult.contents().assumingMemoryBound(to: Float.self)
//        var fail = 0
//        for i in 0 ..< count {
//            let result = a[i] + b[i]
//            if result != r[i] {
//                print("Expected \(result) @\(i) but got \(r[i])")
//                fail += 1
//            }
//        }
//        print("checked \(bufferSize) results, found \(fail) failures")
//    }
}



@MainActor final class RenderController: ObservableObject {
    
    @Published var image: CGImage?
    
    private lazy var renderer = MetalRenderer(
        width: 800,
        height: 400,
        device: MTLCreateSystemDefaultDevice()!
    )
    
    init() {
        renderer.completion = { [weak self] image in
            Task { @MainActor in
                self?.image = image
            }
        }
    }
    
    func start() {
        renderer.render()
    }
}
