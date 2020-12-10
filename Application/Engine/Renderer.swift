import MetalKit
import MetalPerformanceShaders

/// THESE UNIFORMS SHOULD BE MERGED

/// - Remark: Maybe you should always use SIMD types to be extra clear.
struct Uniforms {
    var width: UInt32 = 0
    var height: UInt32 = 0
    var frameIndex: UInt32 = 0
    
    // This should be precalculated
    var fov: Float = 0
    var timer: Float = 0
    var cameraDistance: Float = 0
    
    var rotationMatrix = float3x3(1.0)
    
    // Bounces needs to be an Int why?
    var bounces: Int = 3
}

/// - Important: Shader Uniforms should ALWAYS be initialized. NEVER use optionals.
struct RasterizerUniforms {
    var viewMatrix = float4x4(1.0)
    var projectionMatrix = float4x4(1.0)
    var viewProjectionMatrix = float4x4(1.0)
    var width: UInt32 = 0
    var height: UInt32 = 0
    var frameIndex: UInt32 = 0
    var jitter = SIMD2<Float>(repeating: 0)
}

// For triple buffered copies of our uniforms
let maxFramesInFlight = 3
// Bitwise arithmetic: https://stackoverflow.com/questions/46431114/how-does-this-code-find-the-memory-aligned-size-of-a-struct-in-swift-why-does-i
let alignedUniformsSize = (MemoryLayout<Uniforms>.stride + 255) & ~255

class Renderer: NSObject {
    var device: MTLDevice
    var queue: MTLCommandQueue!
    var library: MTLLibrary!
    
    var renderDestination: RenderDestinationProvider
    
    var uniformBuffer: MTLBuffer!

    var depthStencilState: MTLDepthStencilState!
    var rasterizationPipeline: MTLRenderPipelineState!
    
    var raytracingFunction: MTLFunction!
    var raytracingPipeline: MTLComputePipelineState!
    var copyPipeline: MTLRenderPipelineState!
    
    var useIntersectionFunctions: Bool = false
    var intersectionFunctionTable: MTLIntersectionFunctionTable!
    
    /// This is updated by the view controller when the
    /// NSPanGestureRecognizer responds to user input.
    var delta = simd_float2(0.0, 0.0)

    /// Arcball camera
    var camera: Camera
    var cameraDistance: Float = 15.0
    
    /// Raytracing
    var instanceAccelerationStructure: MTLAccelerationStructure!
    var primitiveAccelerationStructures = [MTLAccelerationStructure]()
    
    /**
        This is assigned a value on startup when the following function is called:
     
            func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    */
    var screenSize = CGSize.zero
    
    var timer: Float = 0
    
    /// Contains camera position, screen resolution etc
    var raytracingUniforms = Uniforms()
    
    /// This allows us to switch between using rasterization
    /// or raytracing to render the scene
    var useRasterization: Bool = false
    
    var useAccumulation: Bool = true
    
    /**
        This texture is created on startup when the following function is called:
     
            func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    */
    var randomTexture: MTLTexture?
    
    /// These have to be optionals since you are initializing them after calling super.init()
    var accumulation: (read: MTLTexture?, write: MTLTexture?)
    var src = 0, dst = 1
    
    var accumulationPipeline: MTLComputePipelineState!
    
    var scene: Scene
    
    var resourceBuffer: MTLBuffer!
    var resourcesStride: UInt32 = 0
    
    var instanceBuffer: MTLBuffer!
    var instanceFuzz: MTLBuffer!
    var instanceColors: MTLBuffer!
    var instanceMaterials: MTLBuffer!
    
    var instanceArgumentBuffer: MTLBuffer!
    
    var inFlightSemaphore: DispatchSemaphore
    
    var uniforms = RasterizerUniforms()
    var prevUniforms = RasterizerUniforms()
    
    var frameIndex: UInt32 = 0
    
    var textureAllocator: MPSSVGFDefaultTextureAllocator!
    var TAA: MPSTemporalAA!
    var denoiser: MPSSVGFDenoiser!
    
    var previousTexture: MTLTexture!
    var previousDepthNormalTexture: MTLTexture!
    
    var haltonSamples = [SIMD2<Float>]()
    
    init(metalDevice device: MTLDevice, scene: Scene, renderDestination: RenderDestinationProvider) {
        self.device = device
        
        self.renderDestination = renderDestination
        
        self.inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        
        self.scene = scene
        
        self.camera = Renderer.setupCamera(distance: 15, rotation: float3(repeating: 0), target: float3(repeating: 0.0))
        
        super.init()
        
        loadMetal()
        loadMPSSVGF()
        createBuffers()
        createAccelerationStructures()
        createPipelines()
        
        /*
        
        guard let dynamicLibrary = try? device.makeDynamicLibrary(library: library) else {
            fatalError("Couldn't create the dynamic library.")
        }
        
        let options = MTLCompileOptions()
        options.libraryType = .dynamic
        options.installName = "@executable_path/myDynamicLibrary.metallib"
        
        // let utilityLib = device.makeLibrary(source: <#T##String#>, options: <#T##MTLCompileOptions?#>)
 
        */
        
        // Argument buffers are created using a MTLFunction so this needs to
        // be called after the raytracingKernel function has been created.
        createArgumentBuffer()
        
        haltonSamples.append(SIMD2<Float>(0.5, 0.333333333333))
        haltonSamples.append(SIMD2<Float>(0.25, 0.666666666667))
        haltonSamples.append(SIMD2<Float>(0.75, 0.111111111111))
        haltonSamples.append(SIMD2<Float>(0.125, 0.444444444444))
        haltonSamples.append(SIMD2<Float>(0.625, 0.777777777778))
        haltonSamples.append(SIMD2<Float>(0.375, 0.222222222222))
        haltonSamples.append(SIMD2<Float>(0.875, 0.555555555556))
        haltonSamples.append(SIMD2<Float>(0.0625, 0.888888888889))
        haltonSamples.append(SIMD2<Float>(0.5625, 0.037037037037))
        haltonSamples.append(SIMD2<Float>(0.3125, 0.37037037037))
        haltonSamples.append(SIMD2<Float>(0.8125, 0.703703703704))
        haltonSamples.append(SIMD2<Float>(0.1875, 0.148148148148))
        haltonSamples.append(SIMD2<Float>(0.6875, 0.481481481481))
        haltonSamples.append(SIMD2<Float>(0.4375, 0.814814814815))
        haltonSamples.append(SIMD2<Float>(0.9375, 0.259259259259))
        haltonSamples.append(SIMD2<Float>(0.03125, 0.592592592593))
    }
    
    // Initialize Metal shader library and command queue.
    func loadMetal() {
        // Load all the shader files with a metal file extension in the project.
        library = device.makeDefaultLibrary()!
        
        // Create the command queue for one frame of rendering work.
        queue = device.makeCommandQueue()!
        
        // Create a depth/stencil state which will be used by the rasterization pipeline
        let descriptor = MTLDepthStencilDescriptor()
        
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        
        depthStencilState = device.makeDepthStencilState(descriptor: descriptor)
    }
    
    func loadMPSSVGF() {
        // Create an object which allocates and caches intermediate textures
        // throughout and across frames
        textureAllocator = MPSSVGFDefaultTextureAllocator(device: device)
        
        // Create an MPSSVGF object. This object encodes the low-level
        // kernels used by the MPSSVGFDenoiser object and allows the app
        // to fine-tune the denoising process.
        // MPSSVGF *svgf = [[MPSSVGF alloc] initWithDevice:_device];
        let svgf = MPSSVGF(device: device)
        
        // Set the channel count to 3 since the application
        // needs to denoise an rgb image.
        svgf.channelCount = 3
        
        // The app integrates samples over time while limiting ghosting artifacts,
        // so set the temporal weighting to an exponential moving average and
        // reduce the temporal blending factor
        svgf.temporalWeighting = .average
        svgf.temporalReprojectionBlendFactor = 0.1
        
        // Create the MPSSVGFDenoiser convenience object. Although you
        // could call the low-level denoising kernels directly on the MPSSVGF
        // object, for simplicity this sample lets the MPSSVGFDenoiser object
        // take care of it.
        denoiser = MPSSVGFDenoiser(SVGF: svgf, textureAllocator: textureAllocator)
        
        // Adjust the number of bilateral filter iterations used by the denoising
        // process. More iterations will tend to produce better quality at the cost
        // of performance, while fewer iterations will perform better but have
        // lower quality. Five iterations is a good starting point. The best way to
        // improve quality is to reduce the amount of noise in the denoiser's input
        // image using techniques such as importance sampling and low-discrepancy
        // random sequences.
        denoiser.bilateralFilterIterations = 5
        
        // Create the temporal antialiasing object
        TAA = MPSTemporalAA(device: device)
    }
    
    // Create a compute pipeline state with an optional array of additional functions to link the compute
    // function with. The sample uses this to link the ray-tracing kernel with any intersection functions.
    func newComputePipelineStateWithFunction(function: MTLFunction, linkedFunctions: [MTLFunction]?) -> MTLComputePipelineState {
        var mtlLinkedFunctions: MTLLinkedFunctions?
        
        if (linkedFunctions != nil) {
            mtlLinkedFunctions = MTLLinkedFunctions()
            
            mtlLinkedFunctions?.functions = linkedFunctions
        }
        
        let descriptor = MTLComputePipelineDescriptor()
        
        // Set the main compute function
        descriptor.computeFunction = function
        
        // Attach the linked functions object to the compute pipeline descriptor.
        descriptor.linkedFunctions = mtlLinkedFunctions
        
        // Set to true to allow the compiler to make certain optimizations.
        descriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
        
        guard let pipeline = try? device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil) else {
            fatalError("Failed to create \(function.name) pipeline state.")
        }
        
        return pipeline
    }
    
    // Create a compute function and specialize its function constants.
    func specializedFunctionWithName(name: String) -> MTLFunction {
        let constants = MTLFunctionConstantValues()
        
        // The first constant is the stride between entries in the resource buffer. The sample
        // uses this to allow intersection functions to look up any resources they use.
        var resourcesStride = self.resourcesStride
        constants.setConstantValue(&resourcesStride, type: .uint, index: 0)
        
        // The second constant turns the use of intersection functions on and off.
        constants.setConstantValue(&useIntersectionFunctions, type: .bool, index: 1)
        
        // Finally, load the function from the Metal library.
        guard let function = try? library.makeFunction(name: name, constantValues: constants) else {
            fatalError("Failed to create function \(name).")
        }
        
        return function
    }
    
    // Create pipeline states
    func createPipelines() {
        // Check if any scene geometry has an intersection function
        for geometry in scene.geometries {
            if geometry.intersectionFunctionName != nil {
                useIntersectionFunctions = true
            }
        }
        
        // Maps intersection function names to actual MTLFunctions
        var intersectionFunctions = [String: MTLFunction]()
        
        // First, load all the intersection functions since the sample needs them to create the final
        // ray-tracing compute pipeline state.
        for geometry in scene.geometries {
            // Skip if the geometry doesn't have an intersection function.
            if let intersectionFunctionName = geometry.intersectionFunctionName {
                // Skip if the app already loaded it.
                if intersectionFunctions[intersectionFunctionName] != nil {
                    continue
                }
                
                // Specialize function constants used by the intersection function.
                let intersectionFunction = specializedFunctionWithName(name: intersectionFunctionName)
                
                // Add the function to the dictionary
                intersectionFunctions[intersectionFunctionName] = intersectionFunction
            }
        }
            
        raytracingFunction = specializedFunctionWithName(name: "raytracingKernel")
        
        let functions = Array(intersectionFunctions.values)
        // let functions: [MTLFunction] = intersectionFunctions.map { $0.1 }
        
        // Create the compute pipeline state which does all of the ray tracing.
        raytracingPipeline = newComputePipelineStateWithFunction(function: raytracingFunction, linkedFunctions: functions)
    
        // Create the function table
        if useIntersectionFunctions {
            let intersectionFunctionTableDescriptor = MTLIntersectionFunctionTableDescriptor()
            intersectionFunctionTableDescriptor.functionCount = scene.geometries.count
            
            // Create a table large enough to hold all of the intersection functions. Metal
            // links intersection functions into the compute pipeline state, potentially with
            // a different address for each compute pipeline. Therefore, the intersection
            // function table is specific to the compute pipeline state that created it and you
            // can only use it with that pipeline.
            intersectionFunctionTable = raytracingPipeline.makeIntersectionFunctionTable(descriptor: intersectionFunctionTableDescriptor)!
            
            // Bind the buffer used to pass resources to the intersection functions.
            intersectionFunctionTable.setBuffer(resourceBuffer, offset: 0, index: 0)
            
            // Map each piece of scene geometry to its intersection function.
            for geometryIndex in 0..<scene.geometries.count {
                let geometry = scene.geometries[geometryIndex]
                
                if let intersectionFunctionName = geometry.intersectionFunctionName {
                    let intersectionFunction = intersectionFunctions[intersectionFunctionName]
                    
                    // Create a handle to the copy of the intersection function linked into the
                    // ray-tracing compute pipeline state. Create a different handle for each pipeline
                    // it is linked with.
                    let handle = raytracingPipeline.functionHandle(function: intersectionFunction!)
                    
                    // Insert the handle into the intersection function table. This ultimately maps the
                    // geometry's index to its intersection function.
                    intersectionFunctionTable.setFunction(handle, index: geometryIndex)
                }
            }
        }
        
        // Create a render pipeline state which copies the rendered scene into the MTKView and
        // performs simple tone mapping.
        let renderDescriptor = MTLRenderPipelineDescriptor()
        
        // MARK: - How can you do this so that you can reuse the vertexFunction and fragmentFunction variables?
        // var vertexFunction: MTLFunction
        // var fragmentFunction: MTLFunction
        // do {
        //    vertexFunction = library.makeFunction(name: "copyVertex")
        // }
                
        guard let vertexFunction = library.makeFunction(name: "copyVertex"),
              let fragmentFunction = library.makeFunction(name: "copyFragment") else {
                fatalError("The shader functions could not be found/created.")
        }
        
        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        // Initialize the pipeline.
        do {
            try copyPipeline = device.makeRenderPipelineState(descriptor: renderDescriptor)
        } catch let error {
            print("Failed to create copy pipeline state, error \(error)")
        }
        
        
        // Setup rasterization pipeline.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = specializedFunctionWithName(name: "base_vertex")
        pipelineDescriptor.fragmentFunction = specializedFunctionWithName(name: "base_fragment")
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        pipelineDescriptor.colorAttachments[1].pixelFormat = .rgba16Float
        pipelineDescriptor.colorAttachments[2].pixelFormat = .rg16Float
        
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            try rasterizationPipeline = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            print("Failed to create copy pipeline state, error \(error)")
        }
        
        guard let kernelFunction = library.makeFunction(name: "accumulate") else {
            fatalError("Couldn't create the accumulate function.")
        }
        
        do {
            try accumulationPipeline = device.makeComputePipelineState(function: kernelFunction)
        } catch let error {
            print("Failed to create the inversion pipeline, error \(error)")
        }
    }
    
    // Create an argument encoder which encodes references to a set of resources
    // into a buffer.
    func newArgumentEncoderForResources(resources: [MTLResource]) -> MTLArgumentEncoder {
        var arguments = [MTLArgumentDescriptor]()
        
        for resource in resources {
            let argumentDescriptor = MTLArgumentDescriptor()
            
            argumentDescriptor.index = arguments.count
            argumentDescriptor.access = .readOnly
            
            if resource.conforms(to: MTLBuffer.self) {
                argumentDescriptor.dataType = .pointer
            } else if resource.conforms(to: MTLTexture.self) {
                // var texture = MTLTexture(resource)
                
                argumentDescriptor.dataType = .texture
                // argumentDescriptor.textureType =
            }
            
            arguments.append(argumentDescriptor)
        }
        
        guard let encoder = device.makeArgumentEncoder(arguments: arguments) else {
            fatalError("Couldn't create the argument encoder.")
        }
        
        return encoder
    }
    
    func createBuffers() {
        // The uniform buffer contains a few small values which change from frame to frame. The
        // sample can have up to 3 frames in flight at once, so allocate a range of the buffer
        // for each frame. The GPU reads from one chunk while the CPU writes to the next chunk.
        // Align the chunks to 256 bytes on macOS and 16 bytes on iOS.
        let uniformBufferSize = alignedUniformsSize * maxFramesInFlight
        
        let options: MTLResourceOptions = .storageModeShared
        
        uniformBuffer = device.makeBuffer(length: uniformBufferSize, options: options)!
        
        // Upload scene data to buffers
        scene.uploadToBuffers()
        
        // This has already been initialized at the top of Renderer
        resourcesStride = 0
        
        // Each intersection function has its own set of resources. Determine the maximum size over all
        // intersection functions. This will become the stride used by intersection functions to find
        // the starting address for their resources.
        for geometry in scene.geometries {
            let encoder = newArgumentEncoderForResources(resources: geometry.resources)
            
            if encoder.encodedLength > resourcesStride {
                resourcesStride = UInt32(encoder.encodedLength)
            }
        }
        
        // Create the resource buffer.
        resourceBuffer = device.makeBuffer(length: Int(resourcesStride) * scene.geometries.count, options: options)!
        
        for geometryIndex in 0..<scene.geometries.count {
            let geometry = scene.geometries[geometryIndex]
            
            // Create an argument encoder for this geometry's intersection function's resources
            let encoder = newArgumentEncoderForResources(resources: geometry.resources)
            
            // Bind the argument encoder to the resource buffer at this geometry's offset.
            encoder.setArgumentBuffer(resourceBuffer, offset: Int(resourcesStride) * geometryIndex)
            
            // Encode the arguments into the resource buffer.
            for argumentIndex in 0..<geometry.resources.count {
                let resource = geometry.resources[argumentIndex]
                
                if resource.conforms(to: MTLBuffer.self) {
                    // Not sure what the difference is exactly...
                    // encoder.setBuffer((resource as! MTLBuffer), offset: 0, index: argumentIndex)
                    encoder.setBuffer((resource as? MTLBuffer), offset: 0, index: argumentIndex)
                } else if resource.conforms(to: MTLTexture.self) {
                    encoder.setTexture(resource as? MTLTexture, index: argumentIndex)
                }
            }
        }
        
        print("Resources stride", resourcesStride, separator: ": ")
    
        // Equal to the number of resources plus the size of a memory address on a 64-bit system
        print("Resource buffer length", resourceBuffer.length, separator: ": ")
        
        // #if !TARGET_OS_IPHONE (i.e. has to be storageModeManaged)
        // resourceBuffer.didModifyRange(0..<resourceBuffer.length)
    }
    
    func createArgumentBuffer() {
        let argumentEncoder = raytracingFunction.makeArgumentEncoder(bufferIndex: 2)
        
        let argumentBufferLength = argumentEncoder.encodedLength
        
        instanceArgumentBuffer = device.makeBuffer(length: argumentBufferLength, options: [])
        
        instanceArgumentBuffer.label = "Argument Buffer"
        
        argumentEncoder.setArgumentBuffer(instanceArgumentBuffer, offset: 0)

        argumentEncoder.setBuffer(instanceColors, offset: 0, index: 0)
        argumentEncoder.setBuffer(instanceMaterials, offset: 0, index: 1)
        argumentEncoder.setBuffer(instanceFuzz, offset: 0, index: 2)
        argumentEncoder.setBuffer(instanceBuffer, offset: 0, index: 3)
    }
    
    // Create and compact an acceleration structure, given an acceleration structure descriptor.
    func newAccelerationStructureWithDescriptor(descriptor: MTLAccelerationStructureDescriptor) -> MTLAccelerationStructure {
        // Query for the sizes needed to store and build the acceleration structure.
        let accelSizes = device.accelerationStructureSizes(descriptor: descriptor)
        
        // Allocate an acceleration structure large enough for this descriptor. This doesn't actually
        // build the acceleration structure, just allocates memory.
        guard let accelerationStructure = device.makeAccelerationStructure(size: accelSizes.accelerationStructureSize) else {
            fatalError("Could not allocate memory for the acceleration structure.")
        }
        
        // Allocate scratch space used by Metal to build the acceleration structure.
        // Use MTLResourceStorageModePrivate for best performance since the sample
        // doesn't need access to buffer's contents.
        guard let scratchBuffer = device.makeBuffer(length: accelSizes.buildScratchBufferSize, options: .storageModePrivate) else {
            fatalError("Could not allocate scratch space.")
        }
        
        // Create a command buffer which will perform the acceleration structure build
        var commandBuffer = queue.makeCommandBuffer()
        
        // Create an acceleration structure command encoder.
        var commandEncoder = commandBuffer?.makeAccelerationStructureCommandEncoder()
        
        // Allocate a buffer for Metal to write the compacted accelerated structure's size into.
        guard let compactedSizeBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
            fatalError("Could not allocate a buffer for the compacted acceleration structure's size.")
        }
        
        // Schedule the actual acceleration structure build
        commandEncoder?.build(accelerationStructure: accelerationStructure,
                              descriptor: descriptor,
                              scratchBuffer: scratchBuffer,
                              scratchBufferOffset: 0)
        
        // Compute and write the compacted acceleration structure size into the buffer. You
        // must already have a built accelerated structure because Metal determines the compacted
        // size based on the final size of the acceleration structure. Compacting an acceleration
        // structure can potentially reclaim significant amounts of memory since Metal must
        // create the initial structure using a conservative approach.
        
        commandEncoder?.writeCompactedSize(accelerationStructure: accelerationStructure,
                                           buffer: compactedSizeBuffer,
                                           offset: 0)
        
        // End encoding and commit the command buffer so the GPU can start building the
        // acceleration structure.
        commandEncoder?.endEncoding()
        commandBuffer?.commit()
        
        // The sample waits for Metal to finish executing the command buffer so that it can
        // read back the compacted size.

        // Note: Don't wait for Metal to finish executing the command buffer if you aren't compacting
        // the acceleration structure, as doing so requires CPU/GPU synchronization. You don't have
        // to compact acceleration structures, but you should when creating large static acceleration
        // structures, such as static scene geometry. Avoid compacting acceleration structures that
        // you rebuild every frame, as the synchronization cost may be significant.
        
        commandBuffer?.waitUntilCompleted()
        
        let pointer = compactedSizeBuffer.contents().assumingMemoryBound(to: UInt32.self)
        let compactedSize = pointer.pointee
        
        // Allocate a smaller acceleration structure based on the returned size.
        guard let compactedAccelerationStructure = device.makeAccelerationStructure(size: Int(compactedSize)) else {
            fatalError("Could not allocate memory for the compacted acceleration structure.")
        }
        
        // Create another command buffer and encoder.
        commandBuffer = queue.makeCommandBuffer()
        
        // The fact the command encoder and command buffer are being
        // reused is a good reason to keep them as optionals.
        commandEncoder = commandBuffer?.makeAccelerationStructureCommandEncoder()
        
        // Encode the command to copy and compact the acceleration structure into the
        // smaller acceleration structure.
        commandEncoder?.copyAndCompact(sourceAccelerationStructure: accelerationStructure, destinationAccelerationStructure: compactedAccelerationStructure)
        
        // End encoding and commit the command buffer. You don't need to wait for Metal to finish
        // executing this command buffer as long as you synchronize any ray-intersection work
        // to run after this command buffer completes. The sample relies on Metal's default
        // dependency tracking on resources to automatically synchronize access to the new
        // compacted acceleration structure.
        commandEncoder?.endEncoding()
        commandBuffer?.commit()
        
        return compactedAccelerationStructure
    }
    
    // Create acceleration structures for the scene. The scene contains primitive acceleration
    // structures and an instance acceleration structure. The primitive acceleration structures
    // contain primitives such as triangles and spheres. The instance acceleration structure contains
    // copies or "instances" of the primitive acceleration structures, each with their own
    // transformation matrix describing where to place them in the scene.
    func createAccelerationStructures() {
        let options: MTLResourceOptions = .storageModeShared
        
        // Create a primitive acceleration structure for each piece of geometry in the scene.
        for index in 0..<scene.geometries.count {
            let mesh = scene.geometries[index]
            
            let geometryDescriptor = mesh.geometryDescriptor
            
            // Assign each piece of geometry a consecutive slot in the intersection function table.
            geometryDescriptor.intersectionFunctionTableOffset = index
            
            // Create a primitive acceleration structure descriptor to contain the single piece
            // of acceleration structure geometry.
            let accelDescriptor = MTLPrimitiveAccelerationStructureDescriptor()
            
            accelDescriptor.geometryDescriptors = [ geometryDescriptor ]
            
            // Build the acceleration structure.
            let accelerationStructure = newAccelerationStructureWithDescriptor(descriptor: accelDescriptor)
            
            // Add the acceleration structure to the array of primitive acceleration structures.
            primitiveAccelerationStructures.append(accelerationStructure)
        }
        
        // Allocate a buffer of acceleration structure instance descriptors. Each descriptor represents
        // an instance of one of the primitive acceleration structures created above, with its own
        // transformation matrix.
        instanceBuffer = device.makeBuffer(length: MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride * scene.instances.count, options: options)!
        
        let instanceDescriptors = instanceBuffer.contents().assumingMemoryBound(to: MTLAccelerationStructureInstanceDescriptor.self)
        
        // Append the color of each instance to this array
        // This will let me access the colors for each instance
        // from a buffer using the instance_id to index the buffer
        var fuzz = [Float]()
        var colors = [float3]()
        var materials = [UInt32]()
        
        // Fill out instance descriptors
        for instanceIndex in 0..<scene.instances.count {
            let instance: GeometryInstance = scene.instances[instanceIndex]
            
            
            /*
            
            let geometryIndex = scene.geometries.firstIndex{$0 === instance.geometry}
            // print(instance.geometry is SphereGeometry)
            
            
            
            if let index = geometryIndex {
                print("Geometry index", index, separator: ": ")
            }
 
            */
            
            // let geometryIndex = scene.geometries.firstIndex(of: instance.geometry)
            instanceDescriptors[instanceIndex].accelerationStructureIndex = 0
            
            // MARK: - Could this be a potential cause of the bug?
            
            // Mark the instance as opaque if it doesn't have an intersection function so that the
            // ray intersector doesn't attempt to execute a function that doesn't exist.
            instanceDescriptors[instanceIndex].options = instance.geometry.intersectionFunctionName == nil ? .opaque : []        
            
            // Metal adds the geometry intersection function table offset and instance intersection
            // function table offset together to determine which intersection function to execute.
            // The sample mapped geometries directly to their intersection functions above, so it
            // sets the instance's table offset to 0.
            instanceDescriptors[instanceIndex].intersectionFunctionTableOffset = 0
            
            // Set the instance mask, which the sample uses to filter out intersections between rays
            // and geometry. For example, it uses masks to prevent light sources from being visible
            // to secondary rays, which would result in their contribution being double-counted.
            
            /// - Important: Instances must have the same mask for the same piece of geometry.
            instanceDescriptors[instanceIndex].mask = instance.mask
               
            /**
                Need to convert:
            
                    float4x4(SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
             
                to type:
                    
                    MTLPackedFloat4x3(MTLPackedFloat3, MTLPackedFloat3, MTLPackedFloat3, MTLPackedFloat3)
            */
            
            var col0 = MTLPackedFloat3()
            col0.x = instance.transform[0][0]
            col0.y = instance.transform[0][1]
            col0.z = instance.transform[0][2]
            
            var col1 = MTLPackedFloat3()
            col1.x = instance.transform[1][0]
            col1.y = instance.transform[1][1]
            col1.z = instance.transform[1][2]
            
            var col2 = MTLPackedFloat3()
            col2.x = instance.transform[2][0]
            col2.y = instance.transform[2][1]
            col2.z = instance.transform[2][2]
            
            var col3 = MTLPackedFloat3()
            col3.x = instance.transform[3][0]
            col3.y = instance.transform[3][1]
            col3.z = instance.transform[3][2]
        
            // This is passed to the rasterizer to check the
            // MTLPackedFloat4x3() matrix has been setup correctly
            var transformationMatrix = MTLPackedFloat4x3()
            
            transformationMatrix.columns.0 = col0
            transformationMatrix.columns.1 = col1
            transformationMatrix.columns.2 = col2
            transformationMatrix.columns.3 = col3
            
            instanceDescriptors[instanceIndex].transformationMatrix = transformationMatrix
            
            fuzz.append(instance.fuzz)
            colors.append(instance.color)
            materials.append(instance.material)
        }
        
        // Unavailable in iOS
        // instanceBuffer.didModifyRange(0..<instanceBuffer.length)
        
        // Create an instance acceleration structure descriptor.
        let accelDescriptor = MTLInstanceAccelerationStructureDescriptor()
        
        accelDescriptor.instancedAccelerationStructures = primitiveAccelerationStructures
        accelDescriptor.instanceCount = scene.instances.count
        accelDescriptor.instanceDescriptorBuffer = instanceBuffer
        
        instanceAccelerationStructure = newAccelerationStructureWithDescriptor(descriptor: accelDescriptor)
        
        // Buffer containg the color of each instance which can be indexed using the instance_id
        instanceFuzz = device.makeBuffer(bytes: fuzz, length: fuzz.count * MemoryLayout<Float>.stride)!
        instanceColors = device.makeBuffer(bytes: colors, length: colors.count * MemoryLayout<float3>.stride)!
        instanceMaterials = device.makeBuffer(bytes: materials, length: materials.count * MemoryLayout<UInt32>.stride)!
    }

    // Schedule a draw to happen at a new size.
    func drawRectResized(size: CGSize) {
        // camera.aspect = Float(view.bounds.width) / Float(view.bounds.height)
        camera.aspect = Float(size.width) / Float(size.height)
        self.screenSize = size
        
        print("Screen size: ", size.width, size.height)
        
        // Reset the frame counter so the renderer doesn't try to reproject
        // uninitialized textures into the current frame.
        frameIndex = 0
        
        // Release any textures the denoiser is holding on to, then release
        // everything from the texture allocators.
        denoiser.releaseTemporaryTextures()
        textureAllocator.reset()
        
        // Same as uint
        raytracingUniforms.width = UInt32(size.width)
        raytracingUniforms.height = UInt32(size.height)
        
        /// - Remark: Returns false
        // print(view.drawableSize == size)
        
        /// - Remark: Returns true
        // print(size.width == view.bounds.height)
        
        // Initialize the previous frame's textures
        previousDepthNormalTexture = textureAllocator.texture(with: .rgba16Float, width: Int(size.width), height: Int(size.height))
        previousDepthNormalTexture.label = "Previous depth normal"
        
        previousTexture = textureAllocator.texture(with: .rgba16Float, width: Int(size.width), height: Int(size.height))
        
        randomTexture = Renderer.setupRandomTexture(device: device, width: Int(size.width), height: Int(size.height))
        accumulation = Renderer.setupPingPongTextures(device: device, width: Int(size.width), height: Int(size.height))
    }

    func update() {
        // The sample uses the uniform buffer to stream uniform data to the GPU, so it
        // needs to wait until the GPU finishes processing the oldest GPU frame before
        // it can reuse that space in the buffer.
        //  _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // If this is the first frame or the window has been resized, throw
        // away the temporal history in the denoiser to avoid artifacts.
        
        // This will still work if I am setting the frame index to 0 when
        // the camera moves when using accumulation.
        if frameIndex == 0 {
            denoiser.clearTemporalHistory()
        }
        
        
        // Encode the work into four command buffers. This is complicated by the
        // fact that you need to rebuild an acceleration structure asynchronously
        // in the middle of the frame and you can't encode ray/triangle intersection
        // testing until the acceleration structure has finished building. Start by
        // creating the four command buffers.
        // let shadingCommandBuffer = queue.makeCommandBuffer()!
        // let intersectionCommandBuffer = queue.makeCommandBuffer()!
        // let postprocessingCommandBuffer = queue.makeCommandBuffer()!
        
        // Next, enqueue the command buffers so they run in the correct order. The
        // GPU will start working on them as soon as they are committed, even if
        // they are committed from another thread as in this example.
        // shadingCommandBuffer.enqueue()
        // intersectionCommandBuffer.enqueue()
        // postprocessingCommandBuffer.enqueue()
        
        // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
        // finished proccssing the commands we're encoding this frame.  This indicates when the
        // dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
        // and the GPU.
        
        /*
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            if let strongSelf = self {
                strongSelf.inFlightSemaphore.signal()
            }
        }
        */
            
        updateUniforms()
        updateRaytracingUniforms()
        
        // Note: Completion handlers should be as fast as possible as the GPU driver may
        // have other work scheduled on the underlying dispatch queue.
        
        let commandBuffer = queue.makeCommandBuffer()!
        
        var colorTexture: MTLTexture!, depthNormalTexture: MTLTexture!, motionVectorTexture: MTLTexture!
        
        // In the meantime, you can start working on the initial shading pass.
        // This render pipeline computes lighting/color, depth, normals, motion
        // vectors.
        encodeRasterizationToCommandBuffer(commandBuffer: commandBuffer, colorTexture: &colorTexture, depthNormalTexture: &depthNormalTexture, motionVectorTexture: &motionVectorTexture)
        
        // Commit the shading command buffer. The GPU will start working on
        // shading as soon as it finishes updating the scene and the acceleration
        // structure will be rebuilt simultaneously. This allows the shading work to
        // hide some or all of the latency of rebuilding the acceleration structure.
        // shadingCommandBuffer.commit()
        
        let textureToDenoise = encodeRaytracingKernelToCommandBuffer(commandBuffer: commandBuffer)
        
        if useAccumulation {
            
            // If the camera has moved set the frame index to 0
            if prevUniforms.viewMatrix != uniforms.viewMatrix {
                frameIndex = 0
            }
            
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
            computeEncoder.setComputePipelineState(accumulationPipeline)
            
            computeEncoder.setBytes(&raytracingUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            computeEncoder.setTexture(accumulation.read,  index: src)
            computeEncoder.setTexture(accumulation.write, index: dst)
            computeEncoder.setTexture(textureToDenoise, index: 2)
            
                    
            let w = accumulationPipeline.threadExecutionWidth
            let h = accumulationPipeline.maxTotalThreadsPerThreadgroup / w
            let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
            
            // Since the render target's dimensions are based on the
            // dimensions of the screen, I think these two methods do
            // much the same thing.
            let threadsPerGrid = MTLSize(width: textureToDenoise.width,
                                         height: textureToDenoise.height,
                                         depth: 1)
 
            computeEncoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            computeEncoder.endEncoding()
            
            textureAllocator.return(textureToDenoise)
            
            /*
            
            let width = Int(screenSize.width)
            let height = Int(screenSize.height)
            
            let threadsPerGroup = MTLSizeMake(8, 8, 1)
            let threadGroups = MTLSizeMake((width + threadsPerGroup.width - 1) / threadsPerGroup.width,
                                           (height + threadsPerGroup.height - 1) / threadsPerGroup.height, 1)
            
            computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
 
            */
            
            // Swap the values for each index of the
            // source and destination textures.
            swap(&src, &dst)
            
            if let drawable = renderDestination.currentDrawable {
                if useRasterization {
                    presentDrawableToCommandBuffer(commandBuffer: commandBuffer, drawable: drawable, image: depthNormalTexture)
                } else {
                    presentDrawableToCommandBuffer(commandBuffer: commandBuffer, drawable: drawable, image: accumulation.read)
                }
            }
        } else {
            // The motion vector texture is used 'to describe how much each pixel has moved between frames.'
            // You need to set this up!  Can't be just a float2(0.0) ...
            let denoisedTexture = denoiser.encode(commandBuffer: commandBuffer,
                                                  sourceTexture: textureToDenoise,
                                                  motionVectorTexture: motionVectorTexture,
                                                  depthNormalTexture: depthNormalTexture,
                                                  previousDepthNormalTexture: previousDepthNormalTexture)
            
            // Return the noisy texture back to the texture allocator
            textureAllocator.return(colorTexture)
            textureAllocator.return(textureToDenoise)
            
            // This part is slightly confusing... the application is not doing any compositing
            // so it is unclear when to return textures to the texture allocator.
            var AATexture = denoisedTexture
            
            // You can't stochastically sample the scene geometry for antialiasing
            // when using the MPSSVGF denoiser because it requires a clean depth and
            // normal texture. Instead, you can use post-process temporal antialiasing
            // using the existing motion vectors. You need to wait until you have
            // rendered at least one frame so that the temporal reprojection step will
            // not read an uninitialized texture.
            if frameIndex > 0 {
                AATexture = textureAllocator.texture(with: .rgba16Float, width: Int(screenSize.width), height: Int(screenSize.height))!
                
                TAA.encode(to: commandBuffer,
                           sourceTexture: denoisedTexture,
                           previousTexture: previousTexture,
                           destinationTexture: AATexture,
                           motionVectorTexture: motionVectorTexture,
                           depthTexture: depthNormalTexture)
                
                textureAllocator.return(denoisedTexture)
            }
            
            // Finally, return this frame's 'previous' textures to the texture allocator
            // and make the current frame's depth/normal texture and output texture the
            // next frame's 'previous' textures.
            textureAllocator.return(previousDepthNormalTexture)
            previousDepthNormalTexture = depthNormalTexture
            
            textureAllocator.return(motionVectorTexture)
            
            textureAllocator.return(previousTexture)
            previousTexture = AATexture
            
            if let drawable = renderDestination.currentDrawable {
                if useRasterization {
                    presentDrawableToCommandBuffer(commandBuffer: commandBuffer, drawable: drawable, image: motionVectorTexture)
                } else {
                    presentDrawableToCommandBuffer(commandBuffer: commandBuffer, drawable: drawable, image: AATexture)
                }
            }
        }
        
        // Would it be less confusing just to return all the textures at
        // the end of the draw loop and is there any reason not to?
        
        // Finally, commmit the command buffer.
        commandBuffer.commit()
        
        // Maybe the average that is calculated will be wrong if you
        // do this when the raytracingPipeline isn't running...
        
        // This is no longer the case since both pipelines are running simultaneously
        frameIndex += 1
    }
    
    func encodeRaytracingKernelToCommandBuffer(commandBuffer: MTLCommandBuffer) -> MTLTexture {
        // screenSize is CGSize.zero initially and then
        // set to the current screen size on start up!
        let width = Int(screenSize.width)
        let height = Int(screenSize.height)
        
        // Where does this get returned to the texture allocator?
        let renderTarget = textureAllocator.texture(with: .rgba16Float, width: width, height: height)!
        renderTarget.label = "Raytracing render target"
        
        // Launch a rectangular grid of threads on the GPU to perform ray tracing, with one thread per
        // pixel. The sample needs to align the number of threads to a multiple of the threadgroup
        // size, because earlier, when it created the pipeline objects, it declared that the pipeline
        // would always use a threadgroup size that's a multiple of the thread execution width
        // (SIMD group size). An 8x8 threadgroup is a safe threadgroup size and small enough to be
        // supported on most devices. A more advanced app would choose the threadgroup size dynamically.
        let threadsPerGroup = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake((width + threadsPerGroup.width - 1) / threadsPerGroup.width,
                                       (height + threadsPerGroup.height - 1) / threadsPerGroup.height, 1)
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        computeEncoder.setComputePipelineState(raytracingPipeline)
        computeEncoder.label = "raytracing kernel"
        
        computeEncoder.setBytes(&raytracingUniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        computeEncoder.setBuffer(resourceBuffer, offset: 0, index: 1)
        
        // Indicate to Metal that these resources will be accessed by the GPU and therefore
        // must be mapped to the GPU's address space.
        computeEncoder.useResource(instanceColors, usage: .read)
        computeEncoder.useResource(instanceMaterials, usage: .read)
        computeEncoder.useResource(instanceFuzz, usage: .read)
        computeEncoder.useResource(instanceBuffer, usage: .read)
        
        computeEncoder.setBuffer(instanceArgumentBuffer, offset: 0, index: 2)
        
        computeEncoder.setTexture(renderTarget, index: 0)
        computeEncoder.setTexture(randomTexture, index: 1)
        
        // Bind acceleration structure and intersection function table. These bind to normal buffer
        // binding slots.
        computeEncoder.setAccelerationStructure(instanceAccelerationStructure, bufferIndex: 3)
        computeEncoder.setIntersectionFunctionTable(intersectionFunctionTable, bufferIndex: 4)
        
        // Mark any resources used by intersection functions as "used". The sample does this because
        // it only references these resources indirectly via the resource buffer. Metal makes all the
        // marked resources resident in memory before the intersection functions execute.
        // Normally, the sample would also mark the resource buffer itself since the
        // intersection table references it indirectly. However, the sample also binds the resource
        // buffer directly, so it doesn't need to mark it explicitly.
        for geometry in scene.geometries {
            for resource in geometry.resources {
                computeEncoder.useResource(resource, usage: .read)
            }
        }
        
        // Also mark primitive acceleration structures as used since only the instance acceleration
        // structure references them.
        for accelerationStructure in primitiveAccelerationStructures {
            computeEncoder.useResource(accelerationStructure, usage: .read)
        }
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()
        
        return renderTarget
    }
    
    func updateRaytracingUniforms() {
        raytracingUniforms.fov = camera.fovRadians
        raytracingUniforms.frameIndex = frameIndex
        raytracingUniforms.cameraDistance = cameraDistance
    
        timer += 0.05
        raytracingUniforms.timer = timer.truncatingRemainder(dividingBy: Float.pi * 2.0)
       
        // Camera controls
        // raytracingUniforms.rotationMatrix = makeXZRotationMatrix(angle: delta.x) * makeYZRotationMatrix(angle: delta.y)
        raytracingUniforms.rotationMatrix = makeScaleMatrix(scale: cameraDistance) * makeXZRotationMatrix(angle: delta.x) * makeYZRotationMatrix(angle: delta.y)
    }
    
    // https://en.wikipedia.org/wiki/Rodrigues%27_rotation_formula#Matrix_notation
    
    // Rotation matrix around the z-axis
    func makeXYRotationMatrix(angle: Float) -> simd_float3x3 {
        let rows = [
            simd_float3( cos(angle), sin(angle), 0),
            simd_float3(-sin(angle), cos(angle), 0),
            simd_float3( 0,          0,          1)
        ]
        
        return float3x3(rows: rows)
    }
    
    // Rotation matrix around the y-axis
    func makeXZRotationMatrix(angle: Float) -> simd_float3x3 {
        let rows = [
            simd_float3(cos(angle), 0, -sin(angle)),
            simd_float3(0,          1,  0         ),
            simd_float3(sin(angle), 0,  cos(angle))
        ]
        
        return float3x3(rows: rows)
    }
    
    func makeYZRotationMatrix(angle: Float) -> simd_float3x3 {
        let rows = [
            simd_float3(1,  0,          0         ),
            simd_float3(0,  cos(angle), sin(angle)),
            simd_float3(0, -sin(angle), cos(angle))
        ]
        
        return float3x3(rows: rows)
    }
    
    func makeScaleMatrix(scale: Float) -> simd_float3x3 {
        var matrix = matrix_identity_float3x3
        
        matrix[0, 0] = scale
        matrix[1, 1] = scale
        matrix[2, 2] = scale
        
        return matrix
    }
    
    func makeTranslationMatrix(tx: Float, ty: Float) -> simd_float3x3 {
        var matrix = matrix_identity_float3x3
        
        matrix[2, 0] = tx
        matrix[2, 1] = ty
        
        return matrix
    }
    
    // MARK: - Rasterizer Uniforms
    // Update uniform values that are passed to the GPU.
    func updateUniforms() {
        // Store the previous frame's uniforms before overwriting them
        prevUniforms = uniforms
        
        uniforms.viewMatrix = camera.viewMatrix
        
        // Compute other projection matrix parameters
        // let fieldOfView: Float = 45.0 * (.pi / 180.0)
        let fieldOfView: Float = 70.0 * (.pi / 180.0)
        
        let aspectRatio = Float(screenSize.width) / Float(screenSize.height)
        // let aspectRatio: Float = 1
        
        // Compute the projection matrix
        let projectionMatrix = float4x4(projectionFov: fieldOfView, near: 0.1, far: 1000.0, aspect: aspectRatio)
        
        // Shear the projection matrix by plus or minus half a pixel for temporal
        // antialiasing. This will have the result of sampling a different point
        // within each pixel every frame. The sample uses a Halton sequence rather
        // than purely random numbers to generate the sample positions to ensure good
        // pixel coverage.
        
        let jitter = (haltonSamples[Int(frameIndex) % 16] * 2.0 - 1.0) / SIMD2<Float>(Float(screenSize.width), Float(screenSize.height))
        
        // Store the amount of jitter so that the shader can "unjitter" it
        // when computing motion vectors.
        uniforms.jitter = jitter * SIMD2<Float>(0.5, -0.5)
        
        /*
        
        print("Column 2", projectionMatrix[2])
        
        print("Columns[2, 0]", projectionMatrix[2, 0])
        print("Columns[2, 1]", projectionMatrix[2, 0])
        
        projectionMatrix[2, 0] += jitter.x
        projectionMatrix[2, 1] += jitter.y
        
        print("Columns[2, 0]", projectionMatrix[2, 0])
        print("Columns[2, 1]", projectionMatrix[2, 0])
 
        */
        
        uniforms.projectionMatrix = projectionMatrix
        uniforms.viewProjectionMatrix = projectionMatrix * camera.viewMatrix
        
        uniforms.width = UInt32(screenSize.width)
        uniforms.height = UInt32(screenSize.height)
        
        uniforms.frameIndex = frameIndex
    }

    // Uses the rasterizer to draw the scene geometry. Outputs:
    //   - Shaded color/lighting
    //   - Depth and normals
    //   - Motion vectors describing how far each pixel has moved since the previous frame
    func encodeRasterizationToCommandBuffer(commandBuffer: MTLCommandBuffer,
                                            colorTexture: inout MTLTexture?,
                                            depthNormalTexture: inout MTLTexture?,
                                            motionVectorTexture: inout MTLTexture?) {
        
        colorTexture = textureAllocator.texture(with: .rgba16Float, width: Int(screenSize.width), height: Int(screenSize.height))!
        colorTexture?.label = "Color texture"
        
        depthNormalTexture = textureAllocator.texture(with: .rgba16Float, width: Int(screenSize.width), height: Int(screenSize.height))!
        depthNormalTexture?.label = "Depth normal texture"
        
        motionVectorTexture = textureAllocator.texture(with: .rg16Float, width: Int(screenSize.width), height: Int(screenSize.height))!
        motionVectorTexture?.label = "Motion vector texture"
        
        let depthTexture = textureAllocator.texture(with: .depth32Float, width: Int(screenSize.width), height: Int(screenSize.height))!
        depthTexture.label = "Depth texture"
        
        // Bind the output textures using a render pass descriptor. This also
        // clears the textures to some predetermined values.
        let renderPass = MTLRenderPassDescriptor()
        
        renderPass.colorAttachments[0].texture = colorTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0.5, 0.7, 1.0, 1.0)
        renderPass.colorAttachments[0].storeAction = .store
        
        renderPass.colorAttachments[1].texture = depthNormalTexture
        renderPass.colorAttachments[1].loadAction = .clear
        
        /// - Important: The r channel represents the depth and should be set to the
        /// value of the far clipping plane, which in this case is 1000.
        renderPass.colorAttachments[1].clearColor = MTLClearColorMake(1000.0, 0.0, 0.0, 0.0)
        renderPass.colorAttachments[1].storeAction = .store
        
        renderPass.colorAttachments[2].texture = motionVectorTexture
        renderPass.colorAttachments[2].loadAction = .clear
        renderPass.colorAttachments[2].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        renderPass.colorAttachments[2].storeAction = .store
        
        renderPass.depthAttachment.texture = depthTexture
        renderPass.depthAttachment.loadAction = .clear
        renderPass.depthAttachment.clearDepth = 1.0
        renderPass.depthAttachment.storeAction = .dontCare
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
        
        // Provide current frame and previous frame's uniform data so that
        // the renderer can compute motion vectors.
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<RasterizerUniforms>.stride, index: 0)
        renderEncoder.setVertexBytes(&prevUniforms, length: MemoryLayout<RasterizerUniforms>.stride, index: 1)
        
        // Create an argument buffer for the vertexFunction?
        renderEncoder.setVertexBuffer(resourceBuffer, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 3)
        renderEncoder.setVertexBuffer(instanceColors, offset: 0, index: 4)
        
        // All of the objects are packed into one set of vertex buffers,
        // so you need to bind them at this object's offset. Provide both
        // the current frame and previous frame's vertex data.
        
        /** - Remark: This is unecessary for now since the motion vector will
                      just be float2(0.0) since the scene geometry is static.
        */
        
        // N.B. I think the above is actually incorrect...
        
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RasterizerUniforms>.stride, index: 0)
        renderEncoder.setFragmentBytes(&prevUniforms, length: MemoryLayout<RasterizerUniforms>.stride, index: 1)
        
        renderEncoder.setRenderPipelineState(rasterizationPipeline)
        
        renderEncoder.setDepthStencilState(depthStencilState)
        
        for geometry in scene.geometries {
            for resource in geometry.resources {
                renderEncoder.useResource(resource, usage: .read)
            }
        }
                
        for geometry in scene.geometries {
            if let triangleGeometry = geometry as? TriangleGeometry {
                                
                let vertexCount = triangleGeometry.vertexCount
                // print(vertexCount)
                
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: scene.instances.count)
            }
        }

        renderEncoder.endEncoding()
                
        textureAllocator.return(depthTexture)
    }
    
    func presentDrawableToCommandBuffer(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable, image: MTLTexture?) {
        // Copy the resulting image into the view using the graphics pipeline since the sample
        // can't write directly to it using the compute kernel. The sample delays getting the
        // current render pass descriptor as long as possible to avoid a lenghty stall waiting
        // for the GPU/compositor to release a drawable. The drawable may be nil if
        // the window moved off screen.
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setRenderPipelineState(copyPipeline)
        
        renderEncoder.setFragmentTexture(image, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.endEncoding()
    
        commandBuffer.present(drawable)
    }
}
