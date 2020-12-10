//
//  ViewController.swift
//  MTLRaytracing-iOS
//
//  Created by Eoin Roe on 09/11/2020.
//

import UIKit
import Metal
import MetalKit

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    // var depthPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {}

class ViewController: UIViewController, MTKViewDelegate {
    var renderer: Renderer!
    
    static var previousScale: CGFloat = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        // Set the view to use the default device.
        if let view = self.view as? MTKView {
            view.device = MTLCreateSystemDefaultDevice()
            view.backgroundColor = UIColor.clear
            view.colorPixelFormat = .rgba16Float
            view.depthStencilPixelFormat = .depth32Float
            view.delegate = self
            
            // Returns the screen object representing the devices screen
            let main = UIScreen.main
            let maximumFramesPerSecond = main.maximumFramesPerSecond
            
            print("Maximum frames per second: ", maximumFramesPerSecond)
            
            // Using an MTKView object is the recommended
            // way to adjust your app’s frame rate.
            // view.preferredFramesPerSecond = maximumFramesPerSecond
            
            // Info.plist
            // <key>CADisableMinimumFrameDuration</key>
            // <true/>

            guard view.device != nil else {
                print("Metal is not supported on this device")
                return
            }
            
            let scene = Scene.newRaytracingInOneWeekendScene(device: view.device!)
            
            // Configure the renderer to draw to the view.
            renderer = Renderer(metalDevice: view.device!, scene: scene, renderDestination: view)
            
            // Schedule the screen to be drawn for the first time.
            renderer.drawRectResized(size: view.bounds.size)
            
            addGestureRecognizers(to: view)
            
            // let value = UIInterfaceOrientation.landscapeLeft.rawValue
            // UIDevice.current.setValue(value, forKey: "orientation")
        }
    }
    
    /*
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscapeRight
    }
    
    override public var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    */
    

    // MARK: - MTKViewDelegate
    
    // Called whenever view changes orientation or size.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Schedule the screen to be redrawn at the new size.
        renderer.drawRectResized(size: size)
    }
    
    // Implements the main rendering loop.
    func draw(in view: MTKView) {
        renderer.update()
    }
    
    
    // MARK: - Gesture Recognizers
    
    func addGestureRecognizers(to view: UIView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(gesture:)))
        tap.numberOfTapsRequired = 1
        
        view.addGestureRecognizer(tap)
        
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_ :)))
        press.minimumPressDuration = 1.0
        
        view.addGestureRecognizer(press)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gesture:)))
        view.addGestureRecognizer(pan)
      
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(gesture:)))
        view.addGestureRecognizer(pinch)
    }
    
    // Add controls so you can view each stage of the pipeline
    // i.e. a debug option so you can view the motion vector
    // texture and the depth normal texture etc.
    
    // MARK: - Toggle denoising
    
    @objc func handleTap(gesture: UITapGestureRecognizer) {
        renderer.useAccumulation = !renderer.useAccumulation
        
        // This has to be reset also since the accumulation
        // won't be happening when the denoiser is running,
        // which means the images won't match up when you
        // switch back...
        renderer?.frameIndex = 0
    }
    
    // MARK: - Debug view
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        if (sender.state == UIGestureRecognizer.State.began) {
            print("Long Press")
        
            renderer.useRasterization = !renderer.useRasterization
        }
    }
    
    
    // MARK: - Camera controls
    
    @objc func handlePan(gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        
        let delta = float2(Float(translation.x),
                           Float(translation.y))
      
        renderer?.camera.rotate(delta: delta, sensitivity: 0.001)
        
        // This controls the rotation matrix used by the
        // raytracing kernel.
        renderer?.delta.x -= Float(translation.x) * 0.001
        renderer?.delta.y += Float(translation.y) * 0.001
        
        // Reset
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
        let sensitivity: Float = 50
        let delta = Float(gesture.scale - ViewController.previousScale) * sensitivity
        
        renderer?.camera.zoom(delta: delta)
        renderer?.cameraDistance -= delta * 0.05
        
        ViewController.previousScale = gesture.scale
        
        if gesture.state == .ended {
            ViewController.previousScale = 1
        }
    }
}
