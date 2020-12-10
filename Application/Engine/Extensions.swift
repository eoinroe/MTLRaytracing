import MetalKit
import MetalPerformanceShaders

extension Renderer {
    /// Used in Scene.newRaytracingInOneWeekendScene(...)
    static func setupSphereGeometry(device: MTLDevice, extent: float3) -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: device)

        let mdlMesh = MDLMesh.init(sphereWithExtent: extent, segments: SIMD2<UInt32>(repeating: 50), inwardNormals: false, geometryType: .triangles, allocator: allocator)

        guard let mesh = try? MTKMesh(mesh: mdlMesh, device: device) else {
            fatalError("The sphere mesh could not be created.")
        }

        return mesh
    }

    /// Camera class borrowed from Metal by Tutorials.  Permitted under the Razeware license.
    static func setupCamera(distance: Float, rotation: float3, target: float3) -> Camera {
        let camera = ArcballCamera()
        camera.distance = distance
        camera.rotation = rotation
        camera.target = target
        return camera
    }
    
    static func setupRenderTarget(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        // descriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private
        
        return device.makeTexture(descriptor: descriptor)
    }
    
    static func setupPingPongTextures(device: MTLDevice, width: Int, height: Int) -> (read: MTLTexture?, write: MTLTexture?) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .private
        
        /*
         
        guard let textureA = device.makeTexture(descriptor: descriptor),
              let textureB = device.makeTexture(descriptor: descriptor) else {
                fatalError("The textures couldn't be created.")
        }
        
        return (textureA, textureB)
 
        */
 
        // These are optionals:
        let texture = device.makeTexture(descriptor: descriptor)
        return (texture, texture)
    }
    
    static func setupRandomTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        
        #if os(OSX)
            descriptor.storageMode = .managed
        #elseif os(iOS)
            descriptor.storageMode = .shared
        #endif
        
        let texture = device.makeTexture(descriptor: descriptor)
        
        // Similar to the rays, you need a random value for each pixel
        var randomValues: [UInt32] = []
        
        /*
         Obj-C way of doing things:
         
         uint32_t *randomValues = (uint32_t *)malloc(sizeof(uint32_t) * size.width * size.height);
         
         Trying to translate to Swift:
         
         randomValues.reserveCapacity(MemoryLayout<UInt32>.stride * Int(size.width) * Int(size.height))
         
         for i in 0..<randomValues.capacity {
             randomValues[i] = 1
         }
         
        */
        
        let pixels: Int = width * height
        // print(pixels)
        
        let range: ClosedRange<UInt32> = 0...(1024 * 1024)
        
        for _ in 0..<pixels {
            randomValues.append(UInt32.random(in: range))
        }
        
        // Sample the random texture to see what is there.
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: randomValues,
                        bytesPerRow: MemoryLayout<UInt32>.stride * width)
        
        return texture
    }
    
    static func setupDenoiser(device: MTLDevice) -> MPSSVGFDenoiser {
        // Create an object which allocates and caches intermediate textures
        // throughout and across frames
        // _textureAllocator = [[MPSSVGFDefaultTextureAllocator alloc] initWithDevice:_device];
        let textureAllocator = MPSSVGFDefaultTextureAllocator(device: device)
        
        // Create an MPSSVGF object. This object encodes the low-level
        // kernels used by the MPSSVGFDenoiser object and allows the app
        // to fine-tune the denoising process.
        // MPSSVGF *svgf = [[MPSSVGF alloc] initWithDevice:_device];
        let svgf = MPSSVGF(device: device)
        
        // The app only denoises shadows which only have a single-channel,
        // so set the channel count to 1. This is faster then denoising
        // all 3 channels on an RGB image.
        svgf.channelCount = 1;
        
        // The app integrates samples over time while limiting ghosting artifacts,
        // so set the temporal weighting to an exponential moving average and
        // reduce the temporal blending factor
        svgf.temporalWeighting = .average
        svgf.temporalReprojectionBlendFactor = 0.1
        
        // Create the MPSSVGFDenoiser convenience object. Although you
        // could call the low-level denoising kernels directly on the MPSSVGF
        // object, for simplicity this sample lets the MPSSVGFDenoiser object
        // take care of it.
        let denoiser = MPSSVGFDenoiser(SVGF: svgf, textureAllocator: textureAllocator)
        
        // Adjust the number of bilateral filter iterations used by the denoising
        // process. More iterations will tend to produce better quality at the cost
        // of performance, while fewer iterations will perform better but have
        // lower quality. Five iterations is a good starting point. The best way to
        // improve quality is to reduce the amount of noise in the denoiser's input
        // image using techniques such as importance sampling and low-discrepancy
        // random sequences.
        denoiser.bilateralFilterIterations = 5
        
        // Create the temporal antialiasing object
        // let TAA = MPSTemporalAA(device: device)
            
        return denoiser
    }
}
