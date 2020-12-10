import MetalKit

struct BoundingBox {
    // From MTLAccelerationStructureTypes.h
    var min = MTLPackedFloat3()
    var max = MTLPackedFloat3()
}

struct Sphere {
    var origin: float3
    var radius: Float
    var color: float3
    var material_index: UInt32
    var fuzz: Float
}

class SphereGeometry: NSObject, Geometry {    
    var device: MTLDevice
        
    var sphereBuffer: MTLBuffer!
    var boundingBoxBuffer: MTLBuffer!
    
    var spheres = [Sphere]()
    
    required init(device: MTLDevice) {
        self.device = device
        super.init()
    }
    
    func uploadToBuffers() {
        // #if !TARGET_OS_IPHONE
        // let options: MTLResourceOptions = .storageModeManaged
        let options: MTLResourceOptions = .storageModeShared
        
        sphereBuffer = device.makeBuffer(length: spheres.count * MemoryLayout<Sphere>.stride, options: options)
        boundingBoxBuffer = device.makeBuffer(length: spheres.count * MemoryLayout<BoundingBox>.stride, options: options)
        
        // Initialize empty array
        var boundingBoxes = [BoundingBox]()
    
        for sphere in spheres {
            // Check this has been initalized to 0, 0, 0
            var bounds = BoundingBox()
            
            bounds.min.x = sphere.origin.x - sphere.radius
            bounds.min.y = sphere.origin.y - sphere.radius
            bounds.min.z = sphere.origin.z - sphere.radius
            
            bounds.max.x = sphere.origin.x + sphere.radius
            bounds.max.y = sphere.origin.y + sphere.radius
            bounds.max.z = sphere.origin.z + sphere.radius
            
            boundingBoxes.append(bounds)
        }
        
        sphereBuffer.contents().copyMemory(from: spheres, byteCount: sphereBuffer.length)
        boundingBoxBuffer.contents().copyMemory(from: boundingBoxes, byteCount: boundingBoxBuffer.length)
        
        /**
         Other option:
             
             sphereBuffer = device.makeBuffer(bytes: spheres, length: spheres.count * MemoryLayout<Sphere>.stride, options: .storageModeManaged)
         */
    }
    
    func clear() {
        // _spheres.clear() - In C++ clear() removes all elements from the vector
        // (which are destroyed), leaving the container with a size of 0.
        spheres.removeAll()
    }
    
    func addSphereWithOrigin(origin: float3, radius: Float, color: float3, index: UInt32, fuzz: Float = 0.0) {
        let sphere = Sphere(origin: origin, radius: radius, color: color, material_index: index, fuzz: fuzz)
        spheres.append(sphere)
    }
    
    var geometryDescriptor: MTLAccelerationStructureGeometryDescriptor {
        // Metal represents each piece of geometry in an acceleration structure using
        // a geometry descriptor. The sample uses a bounding box geometry descriptor to
        // represent a custom primitive type
        
        let descriptor = MTLAccelerationStructureBoundingBoxGeometryDescriptor()
        
        // I think this is the only place the boundingBoxBuffer is actually used...
        descriptor.boundingBoxBuffer = boundingBoxBuffer
        descriptor.boundingBoxCount = spheres.count
        
        return descriptor
    }
    
    var resources: [MTLResource] {
        return [self.sphereBuffer]
    }
    
    var intersectionFunctionName: String? {
        return "sphereIntersectionFunction"
    }
}
