//
//  Shaders.metal
//  MTLRaytracing
//
//  Created by Eoin Roe on 24/09/2020.
//

#include <metal_stdlib>
#include <simd/simd.h>
// #include <metal_refraction>

using namespace metal;

using namespace raytracing;

constant unsigned int resourcesStride  [[function_constant(0)]];
constant bool useIntersectionFunctions [[function_constant(1)]];

// #include <metal_array>
constant array<unsigned int, 24> prime_numbers = { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89 };

// Returns the i'th element of the Halton sequence using the d'th prime number as a
// base. The Halton sequence is a "low discrepency" sequence: the values appear
// random but are more evenly distributed then a purely random sequence. Each random
// value used to render the image should use a different independent dimension 'd',
// and each sample (frame) should use a different index 'i'. To decorrelate each
// pixel, a random offset can be applied to 'i'.
float halton(unsigned int i, unsigned int d) {
    // Make sure we don't index outside the bounds of the array
    unsigned int index = d % prime_numbers.size();
    
    unsigned int b = prime_numbers[index];
    
    float f = 1.0f;
    float invB = 1.0f / b;
    
    float r = 0;
    
    while (i > 0) {
        f = f * invB;
        r = r + f * (i % b);
        i = i / b;
    }
    
    return r;
}
 
struct Uniforms {
    unsigned int width;
    unsigned int height;
    unsigned int frameIndex;
    float fov;
    float timer;
    float cameraDistance;
    float3x3 rotationMatrix;
    int bounces;
};

// Camera coordinate system - set to left handed
constant float3 forward = float3(0.0, 0.0, 1.0);
constant float3 right   = float3(1.0, 0.0, 0.0);
constant float3 up      = float3(0.0, 1.0, 0.0);

__attribute__((always_inline))
float3 transformPoint(float3 p, float4x4 transform) {
    return (transform * float4(p.x, p.y, p.z, 1.0f)).xyz;
}

__attribute__((always_inline))
float3 transformDirection(float3 p, float4x4 transform) {
    return (transform * float4(p.x, p.y, p.z, 0.0f)).xyz;
}

// Sample area light has 6 parameters
ray generateCameraRay(uint2 tid,
                      unsigned int width,
                      unsigned int height,
                      unsigned int random_offset,
                      float3x3 cameraTransform) {
    ray ray;
    
    // Pixel coordinates for this thread.
    float2 pixel = (float2)tid;

    // Add a random offset to the pixel coordinates for antialiasing.
    float2 r = float2(halton(random_offset, 0),
                      halton(random_offset, 1));

    pixel += r;

    // Divide the screenspace position of the pixel by the resolution.
    float2 uv = (float2)pixel / float2(width, height);
    
    // Invert the y-coordinate.
    // N.B. This is important for this example since the image needs
    // to match the image created by the rasterizer for denoising.
    uv.y = 1.0 - uv.y;
    
    // Map pixel coordinates to -1..1.
    uv = uv * 2.0f - 1.0f;
    
    // This could be pre-calculated...
    float aspectRatio = (float)width / (float)height;
    uv.x *= aspectRatio;
    
    float3 origin = float3(0.0, 0.0, -1.0);
    origin = cameraTransform * origin;
    
    // Can you replace this with a matrix that scales the vector instead?
    // origin *= uniforms.cameraDistance;
    ray.origin = origin;
    
    float fov = (70.0f / 360.0f) * M_PI_F * 2.0f;
    
    float fovFactor = 1.0 / tan(fov * 0.5);
    float3 fwd = float3(0.0, 0.0, fovFactor);
    
    // normalize(T x):
    // Return a vector in the same direction as x but with a length of 1.
    
    // Normalizing doesn't actually seem to make much of a difference...
    // float3 direction = uv.x * right + uv.y * up + fwd;
    float3 direction = normalize(uv.x * right + uv.y * up + fwd * forward);
    
    ray.direction = normalize(cameraTransform * direction);
    
    // Don't limit intersection distance.
    ray.max_distance = INFINITY;
    
    return ray;
}

float3 calculateGradient(uint2 tid, unsigned int height) {
    float y_coordinate = tid.y / height;
    
    // A blue-to-white gradient depending on ray's y-coordinate
    float3 color = mix(float3(0.5, 0.7, 1.0), float3(1.0), y_coordinate);
    
    // float3 color = mix(float3(0.5, 0.7, 1.0), float3(1.0), pow(st.y, 10.0));
    // float3 color = mix(float3(0.5, 0.7, 1.0), float3(1.0), mix(0.0, 0.5, st.y));
    // float3 color = mix(float3(0.0, 0.0, 1.0), float3(1.0), smoothstep(0.0, 1.5, st.y));
    
    return color;
}

// Return type for a bounding box intersection function.
struct BoundingBoxIntersection {
    bool accept    [[accept_intersection]]; // Whether to accept or reject the intersection.
    float distance [[distance]];            // Distance from the ray origin to the intersection point.
};

struct Sphere {
    float3 origin;
    float radius;
    float3 color;
    unsigned int material_index;
    float fuzz;
};

struct TriangleResources {
    device float3 *vertexNormals;
    device float3 *vertexColors;
};

// Resources for a piece of sphere geometry.
struct SphereResources {
    device Sphere *spheres;
};

[[intersection(bounding_box, instancing, triangle_data)]]
BoundingBoxIntersection sphereIntersectionFunction(// Ray parameters passed to the ray intersector below
                                                   float3 origin               [[origin]],
                                                   float3 direction            [[direction]],
                                                   float minDistance           [[min_distance]],
                                                   float maxDistance           [[max_distance]],
                                                   
                                                   // Information about the primitive.
                                                   unsigned int primitiveIndex [[primitive_id]],
                                                   unsigned int geometryIndex  [[geometry_intersection_function_table_offset]],
                                                   // Custom resources bound to the intersection function table.
                                                   device void *resources      [[buffer(0)]])
{
    // Look up the resources for this piece of sphere geometry.
    device SphereResources & sphereResources = *(device SphereResources *)((device char *)resources);

    // Get the actual sphere enclosed in this bounding box.
    device Sphere & sphere = sphereResources.spheres[primitiveIndex];
    
    // Check for intersection between the ray and sphere mathematically.
    float3 oc = origin - sphere.origin;

    float a = dot(direction, direction);
    float b = 2 * dot(oc, direction);
    float c = dot(oc, oc) - sphere.radius * sphere.radius;

    float disc = b * b - 4 * a * c;

    BoundingBoxIntersection ret;

    if (disc <= 0.0f) {
        // If the ray missed the sphere, return false.
        ret.accept = false;
    }
    else {
        // Otherwise, compute the intersection distance.
        ret.distance = (-b - sqrt(disc)) / (2 * a);

        // The intersection function must also check whether the intersection distance is
        // within the acceptable range. Intersection functions do not run in any particular order,
        // so the maximum distance may be different from the one passed into the ray intersector.
        ret.accept = ret.distance >= minDistance && ret.distance <= maxDistance;
    }

    return ret;
}

float3 random_in_unit_sphere(unsigned int random_offset, int bounce) {
    float3 p = float3(halton(random_offset, 2 + bounce * 5 + 5),
                      halton(random_offset, 2 + bounce * 5 + 6),
                      halton(random_offset, 2 + bounce * 5 + 7));
    
    // Can you use length to make sure that this stays inside a sphere?
    p = (p * 2.0) - 1.0;
    
    return p;
}

float schlick(float cosine, float ref_idx) {
    auto r0 = (1-ref_idx) / (1+ref_idx);
    r0 = r0*r0;
    return r0 + (1-r0)*pow((1 - cosine),5);
}

typedef struct Instances {
    device float3 *colors                                              [[id(0)]];
    device unsigned int *materials                                     [[id(1)]];
    device float *fuzz                                                 [[id(2)]];
    device MTLAccelerationStructureInstanceDescriptor *accelDescriptor [[id(3)]];
} Instances;

struct Resources {
    SphereResources sphereResources     [[id(0)]];
    TriangleResources triangleResources [[id(1)]];
};

// -*- Materials -*-
enum {
    materialIndexDiffuse,
    materialIndexMetallic,
    materialIndexGlass
};

enum class material_index {
    diffuse,
    metallic,
    glass
};

#define __METAL_INDEX_OF_REFRACTION_AIR__ 1.000293

struct refractive_index {
    constexpr static constant float air = 1.000293;
    constexpr static constant float glass = 1.52;
    constexpr static constant float water = 1.333;
};

struct eta
{
    static constexpr float air_to_glass()
    {
        return refractive_index::air / refractive_index::glass;
    }
    
    static constexpr float glass_to_air()
    {
        return refractive_index::glass / refractive_index::air;
    }
};

// For isotropic media, total internal reflection cannot occur if
// the second medium has a higher refractive index than the first
struct critical_angle
{
    // Can you just leave this as cos_theta and do the comparison?
    static constexpr float glass_to_air()
    {
        return 0.718276;
        // return precise::asin(refractive_index::air / refractive_index::glass);
    }
    
    // static constexpr float water_to_air()
    // {
    //     return precise::asin(refractive_index::air / refractive_index::water);
    // }
};

struct index_of_refraction
{
    constexpr static constant float air = 1.000293;
    constexpr static constant float glass = 1.52;
    
    static constexpr float air_to_glass()
    {
        return air / glass;
    }
};

struct ratio_of_indices_of_refraction
{
    static constexpr float air_to_glass()
    {
        return index_of_refraction::air / index_of_refraction::glass;
    }
    
    // If the ray is inside glass and outside is air (𝜂 = 1.5 and 𝜂′ = 1.0):
    static constexpr float glass_to_air()
    {
        return index_of_refraction::glass / index_of_refraction::air;
    }
};

struct WorldSpaceData {
    float3 intersectionPoint;
    float3 surfaceNormal;
};

using MaterialFunction = float3(thread ray&,
                                WorldSpaceData,
                                device Instances&,
                                unsigned int,
                                unsigned int,
                                unsigned int);

[[visible]]
float3 diffuseMaterial(thread ray &ray,
                       WorldSpaceData worldSpace,
                       device Instances &instances,
                       unsigned int instanceIndex,
                       unsigned int random_offset,
                       unsigned int bounce)
{
    // Add a small offset to the intersection point to avoid intersecting the same
    // triangle again.
    ray.origin = worldSpace.intersectionPoint + worldSpace.surfaceNormal * 1e-3f;
    
    // Pick a random point inside the tangent unit sphere that is on the same side
    // of the surface as the ray origin.
    ray.direction = worldSpace.surfaceNormal + random_in_unit_sphere(random_offset, bounce);
    
    // Return the surface color.
    return instances.colors[instanceIndex];
}

[[visible]]
float3 metallicMaterial(thread ray &ray,
                        WorldSpaceData worldSpace,
                        device Instances &instances,
                        unsigned int instanceIndex,
                        unsigned int random_offset,
                        unsigned int bounce)
{
    // Add a small offset to the intersection point to avoid intersecting the same
    // triangle again.
    ray.origin = worldSpace.intersectionPoint + worldSpace.surfaceNormal * 1e-3f;
    
    // Reflect the ray about the normal.
    ray.direction = reflect(ray.direction, worldSpace.surfaceNormal);
    
    // -*- Fuzzy reflection -*-
    
    // Randomize the reflected direction by using a small sphere and choosing a new
    // end point for the ray.
    ray.direction += random_in_unit_sphere(random_offset, bounce) * instances.fuzz[instanceIndex];
    
    // Return the surface color.
    return instances.colors[instanceIndex];
}

[[visible]]
float3 glassMaterial(thread ray &ray,
                     WorldSpaceData worldSpace,
                     device Instances &instances,
                     unsigned int instanceIndex,
                     unsigned int random_offset,
                     unsigned int bounce)
{
    // Return the surface color.
    return instances.colors[instanceIndex];
}

void diffuse(thread ray & ray, float3 p, float3 n, unsigned int random_offset, unsigned int bounce) {
    ray.origin = p + n * 1e-3f;
    ray.direction = n + random_in_unit_sphere(random_offset, bounce);
}

void metallic(thread ray & ray, float3 p, float3 n, unsigned int random_offset, unsigned int bounce, float fuzz) {
    ray.origin = p + n * 1e-3f;
    ray.direction = reflect(ray.direction, n) + (random_in_unit_sphere(random_offset, bounce) * fuzz);
}

void glass(thread ray & ray,
           float3 intersectionPoint,
           float3 surfaceNormal,
           bool front_facing,
           unsigned int random_offset,
           unsigned int bounce)
{
    /*
     If the ray and the normal face in the same direction, the ray is inside the object,
     if the ray and the normal face in the opposite direction, then the ray is outside
     the object. This can be determined by taking the dot product of the two vectors,
     where if their dot is positive, the ray is inside the sphere.
    
     If the ray intersects the sphere from the outside, the normal points against the ray.
     If the ray intersects the sphere from the inside, the normal (which always points out)
     points with the ray.
     
     This can be calculated using the dot product:
     
         bool front_face;
         if (dot(ray_direction, outward_normal) > 0.0) {
             // ray is inside the sphere
             normal = -outward_normal;
             front_face = false;
         }
     
     Metal's intersector also provides this results for us:
     
        intersection.triangle_front_facing
     
     N.B. The result of boolean comparison with the dot product should not be the same as
     intersection.triangle_front_facing, however, at present there appears to be an issue
     with the API.
     
     */
    
    bool front_face = dot(ray.direction, surfaceNormal) < 0;
    // bool front_face = intersection.triangle_front_facing;
    
    float3 normal = front_face ?  surfaceNormal
                               : -surfaceNormal;
    
    float eta = front_face ? eta::air_to_glass()
                           : eta::glass_to_air();
    
    float cos_theta = fmin(dot(-ray.direction, normal), 1.0);
    float sin_theta = sqrt(1.0 - cos_theta*cos_theta);
    
    bool cannot_refract = eta * sin_theta > 1.0;
    
    // Generate a random number
    float r = halton(random_offset, bounce);
    
    // Use Schlick's approximation for reflectance.
    if (cannot_refract || schlick(cos_theta, eta) > r) {
        // -*- Must reflect -*-
        
        // Add a small offset to the intersection point to avoid intersecting the same
        // triangle again.
        ray.origin = intersectionPoint + normal * 1e-3f;
        ray.direction = reflect(ray.direction, normal);
    } else {
        // -*- Can refract -*-
        
        // If the ray is being transmitted through the normal it
        // makes sense that you are subtracting this offset from
        // the intersection point even if you have flipped the normal.
        ray.origin = intersectionPoint - normal * 1e-3f;
        ray.direction = refract(ray.direction, normal, eta);
    }
    
    /*
     
    // -*- Calculate Refraction -*-
     
    bool insideSphere = dot(ray.direction, surfaceNormal) > 0.0;
    
    if (insideSphere)
    {
        // -*- ray is exiting the object -*-
        
        // Make sure the refraction ray is
        // spawned somewhere inside the sphere.
        ray.origin = intersectionPoint + surfaceNormal * 1e-3f;
        float eta = ratio_of_indices_of_refraction::glass_to_air();
        
        // Refraction follows a law called Snell’s law, which states that
        // the ratio of the sines of the incident and transmitted angles
        // is equal to the inverse ratio of the indices of refraction of
        // the media:
        // ray.direction = refract(ray.direction, surfaceNormal, eta);
        ray.direction = reflect(ray.direction, surfaceNormal);
    }
    else
    {
        // -*- ray is entering the object -*-
        
        // Add a small offset to the intersection point to avoid intersecting the same
        // triangle again.
        ray.origin = intersectionPoint - surfaceNormal * 1e-3f;
        
        float eta = ratio_of_indices_of_refraction::air_to_glass();
        ray.direction = refract(ray.direction, surfaceNormal, eta);
    }
     
    */
}

kernel void interaction(uint tid [[thread_position_in_grid]],
                        constant uint2& mouse_position,
                        constant Uniforms &uniforms                     [[buffer(0)]],
                        device void *resources                          [[buffer(1)]],
                        device Instances &instances                     [[buffer(2)]],
                        
                        texture2d<float, access::write> colorTexture    [[texture(0)]],
                        texture2d<unsigned int, access::read> randomTex [[texture(1)]],
                        
                        instance_acceleration_structure accelerationStructure     [[buffer(3)]],
                        intersection_function_table<instancing, triangle_data> intersectionFunctionTable [[buffer(4)]])
{
    // Apply a random offset to the random number index to decorrelate pixels.
    // unsigned int random_offset = randomTex.read(mouse_position).r + uniforms.frameIndex;
    
    // Random offset is probably unnecessary for this.
    unsigned int random_offset = 0;

    ray ray = generateCameraRay(mouse_position,
                                uniforms.width,
                                uniforms.height,
                                random_offset,
                                uniforms.rotationMatrix);
    
    // Create an intersector to test for intersection between the ray and the geometry in the scene.
    intersector<instancing, triangle_data> intersector;
    intersection_result<instancing, triangle_data> intersection;
    
    // Check for intersection between the ray and the acceleration structure.
    // intersection = intersector.intersect(ray, accelerationStructure);
    intersection = intersector.intersect(ray, accelerationStructure, intersectionFunctionTable);
    
    // Stop if the ray didn't hit anything and has bounced out of the scene.
    if (intersection.type != intersection_type::none) {
        unsigned int instanceIndex = intersection.instance_id;
        instances.colors[instanceIndex] = float3(0, 0, 0);
    }
}

kernel void raytracingKernel(uint2 tid [[thread_position_in_grid]],
                             constant Uniforms &uniforms                     [[buffer(0)]],
                             device void *resources                          [[buffer(1)]],
                             device Instances &instances                     [[buffer(2)]],
                             
                             texture2d<float, access::write> colorTexture    [[texture(0)]],
                             texture2d<unsigned int, access::read> randomTex [[texture(1)]],
                             
                             instance_acceleration_structure accelerationStructure     [[buffer(3)]],
                             intersection_function_table<instancing, triangle_data> intersectionFunctionTable [[buffer(4)]],
                             constant uint2& mouse_position [[buffer(5)]])
{    
    // The sample aligns the thread count to the threadgroup size. which means the thread count
    // may be different than the bounds of the texture. Test to make sure this thread
    // is referencing a pixel within the bounds of the texture.
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        
        // Apply a random offset to the random number index to decorrelate pixels.
        unsigned int random_offset = randomTex.read(tid).r + uniforms.frameIndex;
        
        if (mouse_position.x == tid.x && mouse_position.y == tid.y) {
            // random_offset = 0;
            
            // Generate ray
            ray ray = generateCameraRay(tid,
                                        uniforms.width,
                                        uniforms.height,
                                        random_offset,
                                        uniforms.rotationMatrix);
            
            // Create an intersector to test for intersection between the ray and the geometry in the scene.
            intersector<instancing, triangle_data> intersector;
            intersection_result<instancing, triangle_data> intersection;
            
            // Check for intersection between the ray and the acceleration structure.
            // intersection = intersector.intersect(ray, accelerationStructure);
            intersection = intersector.intersect(ray, accelerationStructure, intersectionFunctionTable);
            
            // Stop if the ray didn't hit anything and has bounced out of the scene.
            if (intersection.type != intersection_type::none) {
                unsigned int instanceIndex = intersection.instance_id;
                
                if (instanceIndex != 0) {
                    instances.colors[instanceIndex] = float3(0, 0, 1);
                    instances.materials[instanceIndex] = materialIndexDiffuse;
                    
                    // instances.materials[instanceIndex] = instances.materials[instanceIndex] == materialIndexDiffuse ? materialIndexMetallic : materialIndexDiffuse;
                }
            }
        }
        
        
        // Generate ray
        ray ray = generateCameraRay(tid,
                                    uniforms.width,
                                    uniforms.height,
                                    random_offset,
                                    uniforms.rotationMatrix);

        // Start with a fully white color. The kernel scales the light each time the
        // ray bounces off of a surface, based on how much of each light component
        // the surface absorbs.
        float3 accumulatedColor = float3(1.0f, 1.0f, 1.0f);
        
        // A blue-to-white gradient depending on ray's y-coordinate
        accumulatedColor *= calculateGradient(tid, uniforms.height);
        
        /*
         
         This is all that the intersector can return:
         
         template <typename...intersection_tags>
         struct intersection_result
         {
             intersection_type type;
             float distance;
             uint primitive_id;
             uint geometry_id;
         
             /// Available only if intersection_tags have instancing.
             uint instance_id;
         
             /// Available only if intersection_tags have triangle_data.
             float2 triangle_barycentric_coord;
             bool triangle_front_facing;
         };
         
         */
                
        // Create an intersector to test for intersection between the ray and the geometry in the scene.
        intersector<instancing, triangle_data> intersector;
        
        // This does not seem to be having any effect on intersection.triangle_front_facing
        // (the default is clockwise).
        // intersector.set_triangle_front_facing_winding(winding::counterclockwise);
       
        intersection_result<instancing, triangle_data> intersection;
        
        // shading
        // -------
        
        // Simulate up to 4 ray bounces. Each bounce will propagate light backwards along the
        // ray's path towards the camera.
        for (int bounce = 0; bounce < uniforms.bounces; bounce++) {
                
            // Check for intersection between the ray and the acceleration structure.
            // intersection = intersector.intersect(ray, accelerationStructure);
            intersection = intersector.intersect(ray, accelerationStructure, intersectionFunctionTable);
            
            // Stop if the ray didn't hit anything and has bounced out of the scene.
            if (intersection.type == intersection_type::none)
                break;
            
            // The ray hit something. Look up the transformation matrix for this instance.
            float4x4 objectToWorldSpaceTransform(1.0f);
            unsigned int instanceIndex = intersection.instance_id;
            
            for (int column = 0; column < 4; column++)
                for (int row = 0; row < 3; row++)
                    objectToWorldSpaceTransform[column][row] = instances.accelDescriptor[instanceIndex].transformationMatrix[column][row];
            
            // Triangle intersection data
            float3 worldSpaceIntersectionPoint = ray.origin + ray.direction * intersection.distance;
            
            // We are only rendering spheres in this example.
            device SphereResources & sphereResources = *(device SphereResources *)((device char *)resources);
            
            // What is this type?
            unsigned primitiveIndex = intersection.primitive_id;
            device Sphere & sphere = sphereResources.spheres[primitiveIndex];
            
            // Transform the sphere's origin from object space to world space.
            float3 worldSpaceOrigin = transformPoint(sphere.origin, objectToWorldSpaceTransform);
           
            // For a sphere, the outward normal is in the direction of the hit point minus the center:
            // vec3 outward_normal = (rec.p - center) / radius;
            // rec.set_face_normal(r, outward_normal);
            
            // Compute the surface normal directly in world space.
            float3 worldSpaceSurfaceNormal = normalize(worldSpaceIntersectionPoint - worldSpaceOrigin);
            
            if (instances.materials[instanceIndex] == materialIndexDiffuse)
            {
                diffuse(ray,
                        worldSpaceIntersectionPoint,
                        worldSpaceSurfaceNormal,
                        random_offset,
                        bounce);
            }
            else if (instances.materials[instanceIndex] == materialIndexMetallic)
            {
                metallic(ray,
                         worldSpaceIntersectionPoint,
                         worldSpaceSurfaceNormal,
                         random_offset,
                         bounce,
                         instances.fuzz[instanceIndex]);
            }
            
            // Refraction follows a law called Snell’s law, which states that the ratio of the sines of the incident
            // and transmitted angles is equal to the inverse ratio of the indices of refraction of the media:
            else if (instances.materials[instanceIndex] == materialIndexGlass)
            {
                glass(ray,
                      worldSpaceIntersectionPoint,
                      worldSpaceSurfaceNormal,
                      intersection.triangle_front_facing,
                      random_offset,
                      bounce);
            }
            
            // The sphere is a uniform color so no need to interpolate the color across the surface.
            float3 surfaceColor = instances.colors[instanceIndex];
            
            // Scale the ray color by the color of the surface. This simulates light being absorbed into
            // the surface.
            accumulatedColor *= surfaceColor;
        }
        
        colorTexture.write(float4(accumulatedColor, 1.0), tid);
    }
}

kernel void accumulate(constant Uniforms &uniforms         [[buffer(0)]],
                       texture2d<float, access::read>  src [[texture(0)]],
                       texture2d<float, access::write> dst [[texture(1)]],
                       texture2d<float> renderTarget       [[texture(2)]],
                       uint2 tid [[thread_position_in_grid]])
{
    if (tid.x < uniforms.width && tid.y < uniforms.height) {
        
        float3 color = renderTarget.read(tid).xyz;
    
        // Average this frame's sample with all of the previous frames.
        if (uniforms.frameIndex > 0) {
            float3 prevColor = src.read(tid).xyz;
            
            // If you simply reset the frame index to 0 then prevColor
            // will be set to 0 with the calculation below.
            prevColor *= uniforms.frameIndex;

            color += prevColor;
            color /= (uniforms.frameIndex + 1);
        }

        dst.write(float4(color, 1.0f), tid);
    }
}

// Screen filling quad in normalized device coordinates.
constant float2 quadVertices[] = {
    float2(-1, -1),
    float2(-1,  1),
    float2( 1,  1),
    float2(-1, -1),
    float2( 1,  1),
    float2( 1, -1)
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut
copyVertex(unsigned short vid [[vertex_id]]) {
    float2 position = quadVertices[vid];
    
    VertexOut out {
        .position = float4(position, 0, 1),
        
        // Moves xy from -1 and 1 to between 0 and 1
        // .uv = position * 0.5f + 0.5f
        
        // Need to flip the y-coordinate to compensate
        // for the image being upside down since we are
        // doing deferred rendering.
        .uv = position * float2(0.5f, -0.5f) + 0.5f
    };
    
    return out;
}

typedef VertexOut FragmentIn;

// Simple fragment shader which copies a texture and applies a simple tonemapping function.
fragment float4 copyFragment(FragmentIn in [[ stage_in ]],
                             texture2d<float, access::sample> tex0)
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);
    
    float3 color = tex0.sample(sam, in.uv).rgb;
    
    // Apply a very simple tonemapping function to reduce the dynamic range of the
    // input image into a range which can be displayed on screen.
    color = color / (1.0f + color);
    
    return float4(color, 1.0f);
}


fragment float4
gammaCorrectionFragment(FragmentIn in [[ stage_in ]],
                        texture2d<float, access::sample> tex0)
{
    // constexpr sampler s;
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none);
    
    float3 color = tex0.sample(sam, in.uv).rgb;
    
    // Divide the color by the number of samples and gamma-correct for gamma=2.0
    // auto scale = 1.0 / samples_per_pixel;
    // r = sqrt(scale * r);
    // g = sqrt(scale * g);
    // b = sqrt(scale * b);
    
    // This application is only using 1 sample per pixel.
    // color = sqrt(color);
    color = clamp(sqrt(color), 0.0, 0.999);
    
    return float4(color, 1.0f);
}
