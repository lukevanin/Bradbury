import Foundation
import CoreGraphics
import MetalKit
import simd



private func generateRandomData(_ buffer: MTLBuffer) {
    let count = buffer.length / MemoryLayout<Float>.stride
    let rawPointer = buffer.contents().bindMemory(to: Float.self, capacity: count)
    for i in 0 ..< count {
        rawPointer[i] = Float(drand48()) // Float.random(in: 0 ..< 1)
    }
}


//struct MaterialParam {
//    var type: UInt32 // +4
//    var albedo: simd_float3 // +4
//    var roughness: simd_float1 // +1
//    var indexOfRefraction: simd_float1 // +1
//    // +2
//};


//struct SphereParam {
//    var center: simd_float3
//    var radius: simd_float1
////    var material: MaterialParam
//}


struct RenderParams {
    var noiseBufferSize: simd_uint1
    var noiseOffset: simd_uint1
    var sampleCount: simd_float1
    var sphereCount: simd_uint1
}


final class MetalRenderer {
    
    typealias Completion = (CGImage) -> Void
    
    var completion: Completion?
    
    private var sampleCount = Float(0)
    
    private let width: Int
    private let height: Int
    private let noiseBufferSize: Int = 4096
    private let device: MTLDevice
    private let library: MTLLibrary
    private let function: MTLFunction
    private let computePipelineState: MTLComputePipelineState
    private let commandQueue: MTLCommandQueue
    private let noiseBuffer: MTLBuffer
    private let worldBuffer: MTLBuffer
    private let accumulatorTexture: MTLTexture
    private let outputTexture: MTLTexture
    private var world: [SphereParam]

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
        self.noiseBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.size * noiseBufferSize,
            options: [.storageModeShared]
        )!
        
        let blueMaterial = MaterialParam(
            type: 0,
            albedo: simd_float3(0.1, 0.2, 0.5),
            roughness: 0,
            indexOfRefraction: 0
        )
        let whiteMaterial = MaterialParam(
            type: 0,
            albedo: simd_float3(0.8, 0.8, 0.8),
            roughness: 0,
            indexOfRefraction: 0
        )
        let yellowMaterial = MaterialParam(
            type: 0,
            albedo: simd_float3(0.8, 0.8, 0),
            roughness: 0,
            indexOfRefraction: 0
        )
        let metalMaterial = MaterialParam(
            type: 1,
            albedo: simd_float3(0.7, 0.7, 0.7),
            roughness: 0.1,
            indexOfRefraction: 0
        )
        let glassMaterial = MaterialParam(
            type: 2,
            albedo: simd_float3(1, 1, 1),
            roughness: 0,
            indexOfRefraction: 1.5
        )

        self.world = [SphereParam]()
        world.append(
            SphereParam(
                center: simd_float3(0, -1000, -1),
                radius: 1000,
                material: MaterialParam(
                    type: 0,
                    albedo: simd_float3(0.5, 0.5, 0.5),
                    roughness: 0,
                    indexOfRefraction: 0
                )
            )
        )
        
        for a in -11 ..< 11 {
            for b in -11 ..< 11 {
                
                let center = simd_float3(
                    Float(a) + 0.9 * Float(drand48()),
                    0.2,
                    Float(b) + 0.9 * Float(drand48())
                )
                let reference = simd_float3(4, 0.2, 0);
                
                if (simd_length(center - reference) > 0.9) {
                    let chooseMaterial = drand48()
                    let sphere: SphereParam
                    if chooseMaterial < 0.8 {
                        let colorA = simd_float3(Float(drand48()), Float(drand48()), Float(drand48()))
                        let colorB = simd_float3(Float(drand48()), Float(drand48()), Float(drand48()))

                        sphere = SphereParam(
                            center: center,
                            radius: 0.2,
                            material: MaterialParam(
                                type: 0,
                                albedo: colorA * colorB,
                                roughness: 0,
                                indexOfRefraction: 0
                            )
                        )
                    }
                    else if chooseMaterial < 0.95 {
                        sphere = SphereParam(
                            center: center,
                            radius: 0.2,
                            material: metalMaterial
                        )
                    }
                    else {
                        sphere = SphereParam(
                            center: center,
                            radius: 0.2,
                            material: glassMaterial
                        )
                    }
                    world.append(sphere)
                }
            }
        }

        world.append(
            SphereParam(
                center: simd_float3(0, 1, 0),
                radius: 1,
                material: glassMaterial
            )
        )

        world.append(
            SphereParam(
                center: simd_float3(-4, 1, 0),
                radius: 1,
                material: whiteMaterial
            )
        )

        world.append(
            SphereParam(
                center: simd_float3(+4, 1, 0),
                radius: 1,
                material: MaterialParam(
                    type: 1,
                    albedo: simd_float3(0.7, 0.6, 0.5),
                    roughness: 0.01,
                    indexOfRefraction: 0
                )
            )
        )

        
//        world.append(
//            SphereParam(
//                center: simd_float3(0, -100.5, -1),
//                radius: 100,
//                material: yellowMaterial
//            )
//        )
//        world.append(
//            SphereParam(
//                center: simd_float3(0, 0, -1),
//                radius: 0.49,
//                material: blueMaterial
//            )
//        )
//        world.append(
//            SphereParam(
//                center: simd_float3(-1, 0, -1),
//                radius: 0.49,
//                material: glassMaterial
//            )
//        )
//        world.append(
//            SphereParam(
//                center: simd_float3(+1, 0, -1),
//                radius: 0.49,
//                material: metalMaterial
//            )
//        )
        self.worldBuffer = device.makeBuffer(
            length: MemoryLayout<SphereParam>.stride * world.count,
            options: [.storageModeShared]
        )!
        let rawPointer = worldBuffer.contents().bindMemory(to: SphereParam.self, capacity: world.count)
        for i in 0 ..< world.count {
            rawPointer[i] = world[i]
        }

    }
    
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
        var environment = RenderParams(
            noiseBufferSize: simd_uint1(noiseBufferSize),
            noiseOffset: 0,
            sampleCount: sampleCount,
            sphereCount: simd_uint1(world.count)
        )
        computeEncoder.setBytes(&environment, length: MemoryLayout<RenderParams>.stride, index: 0)
        
        computeEncoder.setBuffer(worldBuffer, offset: 0, index: 1)

        generateRandomData(noiseBuffer)
        computeEncoder.setBuffer(noiseBuffer, offset: 0, index: 2)

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
