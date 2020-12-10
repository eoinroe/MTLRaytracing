import MetalKit

/*

class Geometry {
    
}
 
*/

protocol Geometry: NSObject {
    // Metal device used to create the acceleration structures.
    var device: MTLDevice { get }
    
    // Name of the intersection function to use for this geometry, or nil
    // for triangles.
    var intersectionFunctionName: String? { get }
    
    // var type: Any? { get }
    // func getType<T>(_ value: T) where T: Geometry
    
    // Initializer.
    init(device: MTLDevice)
    
    // Upload the primitives to Metal buffers so the GPU can access them.
    func uploadToBuffers()
    
    // Reset the geometry, removing all primitives.
    func clear()
    
    // Get the acceleration structure geometry descriptor for this piece of
    // geometry.
    var geometryDescriptor: MTLAccelerationStructureGeometryDescriptor { get }
    
    // Get the array of Metal resources such as buffers and textures to pass
    // to the geometry's intersection function.
    var resources: [MTLResource] { get }
}

