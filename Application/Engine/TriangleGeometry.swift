import Foundation
import MetalKit

struct Vertex {
    // Position
    var x, y, z: Float
    
    // Normal
    var nx, ny, nz: Float
    
    // Texture coordinate
    var s, t: Float
}

class TriangleGeometry: NSObject, Geometry {
    var device: MTLDevice
    
    var intersectionFunctionName: String?
        
    // Rename positions to vertices?
    var positions: [float3] = [], normals: [float3] = [], colors: [float3] = []

    // Replace these with an array?
    var buffers: (positions: MTLBuffer?, normals: MTLBuffer?, colors: MTLBuffer?)
    
    required init(device: MTLDevice) {
        self.device = device
    }
    
    func addMesh(mesh: MTKMesh, pos: float3, color: float3) {
        /*
            guard let mesh = try? MTKMesh(mesh: mdlMesh, device: device) else {
                fatalError("The sphere mesh could not be created.")
            }
        */
        
        /**
            For different types of geometry would you need to loop through the submeshes?
        
            i.e.
        
                for submesh in mesh.submeshes {
                    let indexData = submesh.indexBuffer.buffer.contents().assumingMemoryBound(to: UInt16.self)
                }
        */
        
        let indexData = mesh.submeshes[0].indexBuffer.buffer.contents().assumingMemoryBound(to: UInt16.self)
        let vertexData = mesh.vertexBuffers[0].buffer.contents().assumingMemoryBound(to: Vertex.self)
        
        // UnsafeMutablePointer<UInt16>
        // print(type(of: indexData))
        
        let numIndices = mesh.submeshes[0].indexCount
        
        // Do this outside of the loop
        // This method doesn't let me use geometry_id for colors and materials...
        colors.append(color)
        // materials.append(material)
        
        // I can simply interpolate the colors but this will not work for the materials.
        
        for i in 0..<numIndices {
            let index = Int(indexData[i])
            
            let position = SIMD3<Float>(vertexData[index].x, vertexData[index].y, vertexData[index].z)
            positions.append(position + pos)
            
            let normal = SIMD3<Float>(vertexData[index].nx, vertexData[index].ny, vertexData[index].nz);
            normals.append(normal)
        }
    }
    
    func uploadToBuffers() {        
        buffers.positions = device.makeBuffer(bytes: positions, length: MemoryLayout<float3>.stride * positions.count)
        buffers.normals = device.makeBuffer(bytes: normals, length: MemoryLayout<float3>.stride * normals.count)
        buffers.colors = device.makeBuffer(bytes: colors, length: MemoryLayout<float3>.stride * colors.count)
    }
    
    func clear() {
        positions.removeAll()
        normals.removeAll()
        colors.removeAll()
    }
    
    // This creates one geometry descriptor which is not so ideal...
    // Although I wonder what the cost of storing all the colors really is?
    // It would be interesting to work out what uses more memory - storing
    // more descriptors or more float3 values.
    var geometryDescriptor: MTLAccelerationStructureGeometryDescriptor {
        
        let descriptor = MTLAccelerationStructureTriangleGeometryDescriptor()
        descriptor.vertexBuffer = buffers.positions
        descriptor.vertexStride = MemoryLayout<float3>.stride
        descriptor.triangleCount = positions.count / 3
        
        return descriptor
    }
    
    /**
     
     Unsure what to do here:
     
         - (NSArray <id <MTLResource>> *)resources {
             // The sphere intersection function uses the sphere origins and radii to check for
             // intersection with rays
             return @[ _sphereBuffer ];
         }
     */
    
    // Get the array of Metal resources such as buffers and textures to pass
    // to the geometry's intersection function.
    var resources: [MTLResource] {
        return [buffers.positions!, buffers.normals!]
    }
    
    
    var vertexCount: Int {
        // return buffers.positions!.length / 3
        return buffers.positions!.length / MemoryLayout<float3>.stride
    }
}


