#include <metal_stdlib>
using namespace metal;

// Function constants setup when the shader functions were created.
constant unsigned int resourcesStride  [[function_constant(0)]];
constant bool useIntersectionFunctions [[function_constant(1)]];

struct RasterizerUniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 viewProjectionMatrix;
    unsigned int width;
    unsigned int height;
    unsigned int frameIndex;
    float2 jitter;
};

struct VertexAttributes {
    device float3 *vertexPositions;
    device float3 *vertexNormals;
};

struct VertexOut {
    float4 position [[ position ]];
    float4 prevPosition;
    float3 worldPosition;
    float3 viewPosition;
    float3 normal;
    float3 color;
};

// Fragment shader outputs
struct FragmentOut {
    float4 color                [[color(0)]];
    float4 depthNormal          [[color(1)]];
    float2 motionVector         [[color(2)]];
};

// Computes the lower 3x3 part of the adjoint.
// Use to transform normals with arbitrary
// matrices.The code assumes the last column of m is
// [0,0,0,1]. More info here:
// https://github.com/graphitemaster/normals_revisited
float3x3 adjoint( float4x4 m )
{
    return float3x3(cross(m[1].xyz, m[2].xyz),
                    cross(m[2].xyz, m[0].xyz),
                    cross(m[0].xyz, m[1].xyz));
}

vertex VertexOut
base_vertex(constant RasterizerUniforms &uniforms      [[buffer(0)]],
            constant RasterizerUniforms &prevUniforms  [[buffer(1)]],
            const device void *resources               [[buffer(2)]],
            
            const device MTLAccelerationStructureInstanceDescriptor *instances [[buffer(3)]],
            // const device MTLAccelerationStructureInstanceDescriptor *prevInstances [[buffer(4)]],
            
            const device float3* colors [[buffer(4)]],
            ushort vid [[vertex_id]],
            ushort iid [[instance_id]])
{
    device VertexAttributes & attributes = *(device VertexAttributes *)((device char *)resources + resourcesStride);
    
    float3 position = attributes.vertexPositions[vid];
    float3 normal = attributes.vertexNormals[vid];
    
    float4x4 objectToWorldSpaceTransform(1.0f);
    
    for (int column = 0; column < 4; column++)
        for (int row = 0; row < 3; row++)
            objectToWorldSpaceTransform[column][row] = instances[iid].transformationMatrix[column][row];
    
    float4 worldPosition = objectToWorldSpaceTransform * float4(position, 1.0f);
    
    // The spheres haven't been rotated so this is unnecessary,
    // even if they had been rotated the normals would stay the same?
    float3x3 normalTransform = adjoint(objectToWorldSpaceTransform);
    
    VertexOut out;
    
    /*
     In this instance the world position and previous world position will be identical.
     It will be out.position and out.prevPosition that are different since the camera is
     the dynamic object in the scene.  Only the view matrix will change unless you add
     controls to adjust the fov.
     */
    
    // Compute the vertex position in NDC space for the current and previous frame
    out.position = uniforms.viewProjectionMatrix * worldPosition;
    out.prevPosition = prevUniforms.viewProjectionMatrix * worldPosition;
    
    // Also output the world space and view space positions for shading

    out.worldPosition = worldPosition.xyz;
    out.viewPosition = (uniforms.viewMatrix * worldPosition).xyz;
    
    // Finally, transform and output the normal vector
    out.normal = normalize(normalTransform * normal);
    
    // And look up the color for each instance using the instance id
    out.color = colors[iid];
    
    return out;
}

typedef VertexOut FragmentIn;

fragment FragmentOut
base_fragment(FragmentIn in [[ stage_in ]],
              constant RasterizerUniforms &uniforms      [[buffer(0)]],
              constant RasterizerUniforms &prevUniforms  [[buffer(1)]])
{
    // The rasterizer will have interpolated the world space position and normal for the fragment
    // float3 P = in.worldPosition;
    
    float3 N = normalize(in.normal);
    
    float2 motionVector = 0.0f;
    
    // Compute motion vectors
    if (uniforms.frameIndex > 0) {
        // Map current pixel location to 0..1
        float2 uv = in.position.xy / float2(uniforms.width, uniforms.height);
        
        // Unproject the position from the previous frame then transform it from
        // NDC space to 0..1
        float2 prevUV = in.prevPosition.xy / in.prevPosition.w * float2(0.5f, -0.5f) + 0.5f;
        
        // Next, remove the jittering which was applied for antialiasing from both
        // sets of coordinates
        uv -= uniforms.jitter;
        prevUV -= prevUniforms.jitter;
        
        // Then the motion vector is simply the difference between the two
        motionVector = uv - prevUV;
    }
    
    FragmentOut out {
        .color = float4(in.color, 1.0f),
        .depthNormal = float4(length(in.viewPosition), N),
        .motionVector = motionVector
    };
    
    return out;
}
