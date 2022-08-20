import Foundation
import CoreGraphics
import MetalKit



private func generateRandomData(_ buffer: MTLBuffer) {
    let count = buffer.length / MemoryLayout<Float>.size
    let rawPointer = buffer.contents().assumingMemoryBound(to: Float.self)
    for i in 0 ..< count {
        rawPointer[i] = Float(drand48()) // Float.random(in: 0 ..< 1)
    }
}


final class MetalRenderer {
    
    typealias Completion = (CGImage) -> Void
    
    var completion: Completion?
    
    private var sampleCount = Float(0)
    
    private let width: Int
    private let height: Int
    private let noiseBufferSize: Int = 1024
    private let device: MTLDevice
    private let library: MTLLibrary
    private let function: MTLFunction
    private let computePipelineState: MTLComputePipelineState
    private let commandQueue: MTLCommandQueue
//    private let bufferA: MTLBuffer
//    private let bufferB: MTLBuffer
//    private let bufferResult: MTLBuffer
    private let noiseBuffer: MTLBuffer
    private let accumulatorTexture: MTLTexture
    private let outputTexture: MTLTexture

    init(width: Int, height: Int, device: MTLDevice) {
        self.width = width
        self.height = height
        self.device = device
        self.library = device.makeDefaultLibrary()!
        self.function = library.makeFunction(name: "render")!
        self.computePipelineState = try! device.makeComputePipelineState(function: function)
        self.commandQueue = device.makeCommandQueue()!
        
        self.accumulatorTexture = device.makeTexture(
            descriptor: {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba32Float,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = [.shaderRead, .shaderWrite]
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
                descriptor.usage = [.shaderWrite]
                return descriptor
            }()
        )!
        // TODO: Use cpu write combined mode for write-only buffers
        let bufferSize = MemoryLayout<Float>.size * noiseBufferSize
        self.noiseBuffer = device.makeBuffer(length: bufferSize, options: [.storageModeShared])!
    }
    
//    func prepare() {
//        generateRandomData(bufferA)
//        generateRandomData(bufferB)
//    }
    
    func render() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
//        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
//            switch commandBuffer.status {
//            case .committed:
//                print("comitted")
//            case .notEnqueued:
//                print("not enqueued")
//            case .enqueued:
//                print("enqueued")
//            case .scheduled:
//                print("scheduled")
//            case .completed:
//                let duration = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
//                print("completed \(String(format: "%0.12f", duration)) seconds")
//                self?.outputImage()
//            case .error:
//                print("error")
//            @unknown default:
//                print("unknown")
//            }
//        }
        
        sampleCount += 1
        var environment = render_parameters(
            noise_buffer_size: UInt32(noiseBufferSize),
            noise_offset: 0,
            sample_count: sampleCount
        )
        computeEncoder.setBytes(&environment, length: MemoryLayout<render_parameters>.stride, index: 0)
        
        generateRandomData(noiseBuffer)
        computeEncoder.setBuffer(noiseBuffer, offset: 0, index: 1)

        computeEncoder.setTexture(accumulatorTexture, index: 0)
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
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let duration = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
        print("completed \(String(format: "%0.12f", duration)) seconds")
        self.outputImage()

    }
    
    private func outputImage() {
        guard let image = makeCGImage(texture: outputTexture) else {
            return
        }
        completion?(image)
    }
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
        Task.detached {
            while true {
                await self.renderer.render()
                try await Task.sleep(nanoseconds: UInt64(0.001 * TimeInterval(1_000_000_000)))
            }
        }
    }
}
