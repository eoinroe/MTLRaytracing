import MetalKit

enum Mask: UInt32 {
    case triangle, sphere
}

enum Material: UInt32 {
    case diffuse, metallic, glass
}

class GeometryInstance: NSObject {
    var geometry: Geometry
    
    var transform: matrix_float4x4
    
    var mask: UInt32
    
    var color: float3
    
    var material: UInt32
    
    var fuzz: Float
    
    init(geometry: Geometry, transform: matrix_float4x4, mask: UInt32, color: float3, material: UInt32, fuzz: Float = 0.0) {
        self.geometry = geometry
        self.transform = transform
        self.mask = mask
        self.color = color
        self.material = material
        self.fuzz = fuzz
        
        super.init()
    }
}
