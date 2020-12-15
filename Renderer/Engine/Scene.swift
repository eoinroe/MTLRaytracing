//
//  Scene.swift
//  Raytracing
//
//  Created by Eoin Roe on 14/09/2020.
//  Copyright © 2020 Eoin Roe. All rights reserved.
//

import Foundation
import MetalKit

/// NSObject: The root class of most Obj-C heirarchies.
class Scene: NSObject {
    var device: MTLDevice
    
    var geometries = [Geometry]()
    
    var instances = [GeometryInstance]()
    
    /**
        Ray Tracing in One Weekend does not use lights
    
            var lights = [AreaLight]()
    
            var lightBuffer: MTLBuffer!
    
            var lightCount: UInt32 = 0
    */
    
    var camera: (position: float3, target: float3, up: float3)
    
    struct Sphere {
        var origin: SIMD3<Float>
        var radius: Float
    }
    
    init(device: MTLDevice) {
        self.device = device
        
        camera.position = float3(0.0, 0.0, -1.0)
        camera.target = float3(repeating: 0.0)
        camera.up = float3(0.0, 1.0, 0.0)
    }
    
    func clear() {
        geometries.removeAll()
        instances.removeAll()
    }
    
    /**
     # Protocols as Types

     Protocols don’t actually implement any functionality themselves. Nonetheless, you can use protocols as a fully fledged types in your code. Using a protocol as a type is sometimes called an existential type, which comes from the phrase “there exists a type T such that T conforms to the protocol”.

     You can use a protocol in many places where other types are allowed, including:

     As a parameter type or return type in a function, method, or initializer
     As the type of a constant, variable, or property
     As the type of items in an array, dictionary, or other container
    */
    func addGeometry(mesh: Geometry) {
        geometries.append(mesh)
    }
    
    func addInstance(instance: GeometryInstance) {
        instances.append(instance)
    }
    
    func uploadToBuffers() {
        for geometry in geometries {
            geometry.uploadToBuffers()
        }
    }
    
    /**
     This function is called once in the Obj-C code like this:
     
         Scene *scene = [Scene newInstancedCornellBoxSceneWithDevice:_view.device
                                            useIntersectionFunctions:YES];
     
     Not sure if this function should be static or replaced with a convenience init()
     */
    
    /*
     Once you get instancing setup correctly you can easily switch between scenes.
     
     Using a function that takes position and size and returns the correct transformation matrix.
     
     auto material2 = make_shared<lambertian>(color(0.4, 0.2, 0.1));
     world.add(make_shared<sphere>(point3(-4, 1, 0), 1.0, material2));
     */
    
    /// I am only using intersection functions to create this [scene](https://raytracing.github.io/books/RayTracingInOneWeekend.html#wherenext?/afinalrender)
    static func newRaytracingInOneWeekendScene(device: MTLDevice, useIntersectionFunctions: Bool = true) -> Scene {
        let scene = Scene(device: device)
        
        let sphereGeometry = SphereGeometry(device: device)
        sphereGeometry.addSphereWithOrigin(origin: float3.zero, radius: 1.0, color: float3(1.0, 1.0, 1.0), index: Material.diffuse.rawValue)
        
        scene.addGeometry(mesh: sphereGeometry)
        
        
        let triangleGeometry = TriangleGeometry(device: device)
        
        let sphereMesh = Renderer.setupSphereGeometry(device: device, extent: float3.one)
        triangleGeometry.addMesh(mesh: sphereMesh, pos: float3.zero, color: float3.one)
        
        scene.addGeometry(mesh: triangleGeometry)
        
        
        var instance: GeometryInstance
        
        var transform: float4x4
        var translate, scale: float4x4
        
        /*
         Make sure to use float4x4(scaling: float3) since the matrix created by this
         method is different from the matrix created by float4x4(scaling: Float)
         
         This is important since the memory footprint is being reduced by
         using float4x3 the last column of the matrix will not be included.
        */

        
        // Ground sphere
        translate = float4x4(translation: float3(0, -1000, 0))
        scale = float4x4(scaling: float3(1000, 1000, 1000))
        
        transform = translate * scale
        
        // If not applying gamma correction
        // instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: Mask.sphere.rawValue, color: float3(0.75, 0.75, 0.75), material: Material.diffuse.rawValue)
        
        instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: Mask.sphere.rawValue, color: float3(0.5, 0.5, 0.5), material: Material.diffuse.rawValue)
        
        scene.addInstance(instance: instance)

        // Middle sphere
        translate = float4x4(translation: float3(0, 1, 0))
        scale = float4x4(scaling: float3(1, 1, 1))
        
        transform = translate * scale
        
        instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: Mask.sphere.rawValue, color: float3(1.0, 1.0, 1.0), material: Material.glass.rawValue)
        scene.addInstance(instance: instance)
        
        
        // Back sphere
        translate = float4x4(translation: float3(-4, 1, 0))
        scale = float4x4(scaling: float3(1, 1, 1))
        
        transform = translate * scale
        
        instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: Mask.sphere.rawValue, color: float3(0.4, 0.2, 0.1), material: Material.diffuse.rawValue)
        scene.addInstance(instance: instance)
        
        
        // Front sphere
        translate = float4x4(translation: float3(4, 1, 0))
        scale = float4x4(scaling: float3(1, 1, 1))
        
        transform = translate * scale
        
        // The fuzz for this metallic sphere is simply the default argument of 0.0 so no need to
        instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: Mask.sphere.rawValue, color: float3(0.7, 0.6, 0.5), material: Material.metallic.rawValue)
        scene.addInstance(instance: instance)
        
        // Random spheres
        let range = -11..<11
        
        for a in range {
            for b in range {
                let center = float3(Float(a) + 0.9 * Float.random(in: 0...1), 0.2, Float(b) + Float.random(in: 0...1))
                
                if (center - float3(4, 0.2, 0)).length > 0.9 {
                    translate = float4x4(translation: center)
                    scale = float4x4(scaling: float3(0.2, 0.2, 0.2))
                    
                    transform = translate * scale
                    
                    // If not applying gamma correction
                    // let r = Float.random(in: 0...1)
                    // let g = Float.random(in: 0...1)
                    // let b = Float.random(in: 0...1) 
                    
                    let r = Float.random(in: 0...1) * Float.random(in: 0...1)
                    let g = Float.random(in: 0...1) * Float.random(in: 0...1)
                    let b = Float.random(in: 0...1) * Float.random(in: 0...1)
 
                    let color = SIMD3<Float>(r, g, b)
                    
                    // How was this still working?
                    // instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: UInt32.random(in: 0...1), color: color, material: UInt32.random(in: 0...1))
                    
                    let chooseMaterial = Double.random(in: 0.0...1.0)
                    
                    // if chooseMaterial < 0.8 {
                    if chooseMaterial < 0.65
                    {
                        instance = GeometryInstance(geometry: sphereGeometry,
                                                    transform: transform,
                                                    mask: Mask.sphere.rawValue,
                                                    color: color,
                                                    material: Material.diffuse.rawValue)
                    }
                    // } else if chooseMaterial < 0.95 {
                    else
                    {
                        instance = GeometryInstance(geometry: sphereGeometry,
                                                    transform: transform,
                                                    mask: Mask.sphere.rawValue,
                                                    color: color,
                                                    material: Material.metallic.rawValue,
                                                    fuzz: Float.random(in: 0...0.5))
                    }
                    
                    /*
                     
                     Only including the one big glass sphere since the frame rate is too low otherwise
                     
                     
                     else
                     {
                         color = SIMD3<Float>(repeating: 1.0)
                         
                         instance = GeometryInstance(geometry: sphereGeometry,
                                                     transform: transform,
                                                     mask: Mask.sphere.rawValue,
                                                     color: color,
                                                     material: Material.glass.rawValue)
                     }
                     */
                    
                    
                    /*
                    
                    instance = GeometryInstance(geometry: sphereGeometry, transform: transform, mask: Mask.sphere.rawValue, color: color, material: UInt32.random(in: 0...2), fuzz: Float.random(in: 0...0.5))
 
                    */
                    
                    scene.addInstance(instance: instance)
                }
            }
        }
        
        return scene
    }
    
    static func newTestScene(device: MTLDevice) -> Scene {
        let scene = Scene(device: device)
        
        // This is for the raytracing kernel's intersection functions
        let sphereGeometry = SphereGeometry(device: device)
        sphereGeometry.addSphereWithOrigin(origin: float3.zero, radius: 1.0, color: float3(1.0, 1.0, 1.0), index: Material.diffuse.rawValue)
        
        scene.addGeometry(mesh: sphereGeometry)
        
        // This is for the vertex shader instance
        let triangleGeometry = TriangleGeometry(device: device)
        
        let sphereMesh = Renderer.setupSphereGeometry(device: device, extent: float3.one)
        triangleGeometry.addMesh(mesh: sphereMesh, pos: float3.zero, color: float3.one)
        
        scene.addGeometry(mesh: triangleGeometry)
        
        
        let spheres = positionOnXZPlane(width: 22, depth: 22, count: 22*22)
        
        var instance: GeometryInstance
        var translate, scale: float4x4
        
        // Ground sphere
        translate = float4x4(translation: spheres[0].origin)
        scale = float4x4(scaling: float3(repeating: spheres[0].radius))

        instance = GeometryInstance(geometry: sphereGeometry, transform: translate * scale, mask: Mask.sphere.rawValue, color: float3(0.5, 0.5, 0.5), material: Material.diffuse.rawValue)
        scene.addInstance(instance: instance)
        
        // Middle sphere
        translate = float4x4(translation: spheres[1].origin)
        scale = float4x4(scaling: float3(repeating: spheres[1].radius))

        instance = GeometryInstance(geometry: sphereGeometry, transform: translate * scale, mask: Mask.sphere.rawValue, color: float3(1.0, 1.0, 1.0), material: Material.glass.rawValue)
        scene.addInstance(instance: instance)
        
        // Back sphere
        translate = float4x4(translation: spheres[2].origin)
        scale = float4x4(scaling: float3(repeating: spheres[2].radius))
        
        instance = GeometryInstance(geometry: sphereGeometry, transform: translate * scale, mask: Mask.sphere.rawValue, color: float3(0.4, 0.2, 0.1), material: Material.diffuse.rawValue)
        scene.addInstance(instance: instance)
        
        // Front sphere
        translate = float4x4(translation: spheres[3].origin)
        scale = float4x4(scaling: float3(repeating: spheres[3].radius))
        
        // The fuzz for this metallic sphere is simply the default argument of 0.0 so no need to specify
        instance = GeometryInstance(geometry: sphereGeometry, transform: translate * scale, mask: Mask.sphere.rawValue, color: float3(0.7, 0.6, 0.5), material: Material.metallic.rawValue)
        scene.addInstance(instance: instance)
        
        for index in 4..<spheres.count {
            translate = float4x4(translation: spheres[index].origin)
            scale = float4x4(scaling: float3(repeating: spheres[index].radius))
            
            let chooseMaterial = Double.random(in: 0.0...1.0)
            
            if chooseMaterial < 0.8
            {
                // let r = Float.random(in: 0...1)
                // let g = Float.random(in: 0...1)
                // let b = Float.random(in: 0...1)
                
                // let r = pow(Float.random(in: 0...1), 2)
                // let g = pow(Float.random(in: 0...1), 2)
                // let b = pow(Float.random(in: 0...1), 2)
                
                let r = Float.random(in: 0...1) * Float.random(in: 0...1)
                let g = Float.random(in: 0...1) * Float.random(in: 0...1)
                let b = Float.random(in: 0...1) * Float.random(in: 0...1)
                
                let color = SIMD3<Float>(r, g, b)
                
                instance = GeometryInstance(geometry: sphereGeometry,
                                            transform: translate * scale,
                                            mask: Mask.sphere.rawValue,
                                            color: color,
                                            material: Material.diffuse.rawValue)
            }
            else
            {
                let r = Float.random(in: 0.5...1)
                let g = Float.random(in: 0.5...1)
                let b = Float.random(in: 0.5...1)

                let color = SIMD3<Float>(r, g, b)
                
                instance = GeometryInstance(geometry: sphereGeometry,
                                            transform: translate * scale,
                                            mask: Mask.sphere.rawValue,
                                            color: color,
                                            material: Material.metallic.rawValue,
                                            fuzz: Float.random(in: 0...0.5))
            }
            
            scene.addInstance(instance: instance)
        }
        
        return scene
    }
    
    static func newSphereGeometryScene(device: MTLDevice, sizeOfWorld: Float = 1000) -> Scene {
        
        let scene = Scene(device: device)
        
        let sphereGeometry = SphereGeometry(device: device)
        
        
        let worldOrigin = float3(0.0, (sizeOfWorld + 1) * -1, 0.0)
        
        // Ground
        sphereGeometry.addSphereWithOrigin(origin: worldOrigin,
                                           radius: sizeOfWorld,
                                           color: float3(repeating: 0.5),
                                           index: Material.diffuse.rawValue)
        
        let scale: Float = 10
        
        let offset: Float = 0.015 / scale
        
        var radius: Float = 3.0
        
        var r = radius + sizeOfWorld
        
        // azimuthal
        var θ: Float = .pi * 0.5
            
        // zenith
        var φ: Float = .pi * 0.5
        
        var x = r * cos(θ) * sin(φ)
        var y = r * sin(θ) * sin(φ)
        var z = r * cos(φ)

        // Middle Glass
        sphereGeometry.addSphereWithOrigin(origin: worldOrigin + float3(x, y, z),
                                           radius: radius,
                                           color: float3(repeating: 1.0),
                                           index: Material.glass.rawValue)
        
        
        radius = 3.0
        
        r = radius + sizeOfWorld
        
        // azimuthal
        θ = .pi * (0.5 - offset)
            
        // zenith
        φ = .pi * (0.5 + offset)
        
        x = r * cos(θ) * sin(φ)
        y = r * sin(θ) * sin(φ)
        z = r * cos(φ)
                
        sphereGeometry.addSphereWithOrigin(origin: worldOrigin + float3(x, y, z),
                                           radius: radius,
                                           color: float3(0.7, 0.6, 0.5),
                                           index: Material.metallic.rawValue,
                                           fuzz: 0.0)
        
        radius = 3.0
        
        r = radius + sizeOfWorld
        
        // azimuthal
        θ = .pi * (0.5 + offset)
            
        // zenith
        φ = .pi * (0.5 - offset)
        
        x = r * cos(θ) * sin(φ)
        y = r * sin(θ) * sin(φ)
        z = r * cos(φ)
        
        // Large brown sphere
        sphereGeometry.addSphereWithOrigin(origin: worldOrigin + float3(x, y, z),
                                           radius: radius,
                                           color: float3(0.552, 0.270, 0.109),
                                           index: Material.diffuse.rawValue)
        
        
         
        for _ in 0..<40 {
            
            let radius = Float.random(in: 0.5...1.0)
                
            let r = radius + sizeOfWorld
            let origin = float3(0.0, (sizeOfWorld + 1) * -1, 0.0)
            
            // azimuthal
            var θ: Float = .pi * 0.5
            θ += Float.random(in: -0.15...0.15) / scale
                
            // zenith
            var φ: Float = .pi * 0.5
            φ += Float.random(in: -0.15...0.15) / scale
            
            let x = r * cos(θ) * sin(φ)
            let y = r * sin(θ) * sin(φ)
            let z = r * cos(φ)
            
            sphereGeometry.addSphereWithOrigin(origin: origin + float3(x, y, z),
                                               radius: radius,
                                               color: float3(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)),
                                               index: (UInt32.random(in: 0...100) % 2),
                                               fuzz: Float.random(in: 0...1))
            }
 
            
        
            
            /*
            
            sphereGeometry.addSphereWithOrigin(origin: float3(Float.random(in: -15...15), 0.0, Float.random(in: -15...15)),
                                               radius: Float.random(in: 0.75...1.0),
                                               color: float3(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)),
                                               index: (Int32.random(in: 0...100) % 2),
                                               fuzz: Float.random(in: 0...1))
 
            */
        
        
        scene.addGeometry(mesh: sphereGeometry)
        
        return scene
    }
}

extension Scene {
    static func positionOnXZPlane(width: Float, depth: Float, count: Int) -> [Sphere] {
        var spheres = [Sphere]()
        
        // Ground sphere
        spheres.append(Sphere(origin: SIMD3<Float>(0, -1000, 0), radius: 1000))
        
        // Middle sphere
        spheres.append(Sphere(origin: SIMD3<Float>(0, 1, 0), radius: 1))
        
        // Back sphere
        spheres.append(Sphere(origin: SIMD3<Float>(-4, 1, 0), radius: 1))
        
        // Front sphere
        spheres.append(Sphere(origin: SIMD3<Float>(4, 1, 0), radius: 1))
        
        
        // Start with this radius and decrease the size after a set number of iterations
        var radius: Float = 0.2
        
        // Keep track of the number of iterations
        var iterations = 0
        
        // Random spheres
        let range: Range<Float> = -11..<11
        
        while spheres.count < count {
            iterations += 1
            
            if iterations % 10000 == 0 {
                radius *= 0.9
            }
            
            let x = Float.random(in: range)
            let z = Float.random(in: range)
            
            // Use spherical coordinates to calculate the y-position
            let y = sqrt(pow(1000 + radius, 2) - pow(x, 2) - pow(z, 2))
            
            let sphere = Sphere(origin: SIMD3<Float>(0.0, -1000.0, 0.0) + SIMD3<Float>(x, y, z), radius: radius)
            
            // let y = sqrt(pow(radius, 2) - pow(x, 2) - pow(z, 2))
            // let sphere = Sphere(origin: SIMD3<Float>(x, y, z), radius: radius)
            
            // let sphere = Sphere(origin: SIMD3<Float>(Float.random(in: range), 0.2, Float.random(in: range)), radius: radius)
            
            var overlapping = false
            
            // Don't forget that the first sphere is very wide so the radii of the other
            // spheres will always overlap with it.  Therefore you need to count from 1.
            for i in 1..<spheres.count {
                let d = distance(SIMD2<Float>(sphere.origin.x, sphere.origin.z), SIMD2<Float>(spheres[i].origin.x, spheres[i].origin.z))
                
                if d < sphere.radius + spheres[i].radius {
                    overlapping = true
                    break
                }
            }
            
            if overlapping == false {
                spheres.append(sphere)
            }
            
            if iterations >= 1000000 {
                print("Breaking out of the loop after 1000000 iterations. \(spheres.count) circles added to the array.")
                break
            }
        }
        
        print("Number of iterations used: ", iterations)
            
        return spheres
    }
    
    
}

private extension Scene {
    static func createSphereTransform(radius: Float, sizeOfWorld: Float, offset: Float) -> float4x4 {
        let r = radius + sizeOfWorld
        
        // azimuthal
        let θ = .pi * (0.5 - offset)
            
        // zenith
        let φ = .pi * (0.5 + offset)
        
        let x = r * cos(θ) * sin(φ)
        let y = r * sin(θ) * sin(φ)
        let z = r * cos(φ)
        
        let scale = float4x4(scaling: float3(repeating: radius))
        let translate = float4x4(translation: float3(x, y, z))
        
        return translate * scale
    }
}
