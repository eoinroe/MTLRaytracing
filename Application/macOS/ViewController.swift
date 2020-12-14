//
//  ViewController.swift
//  MTLRaytracing-macOS
//
//  Created by Eoin Roe on 08/12/2020.
//

import Cocoa
import Metal
import MetalKit

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {}

class ViewController: NSViewController, MTKViewDelegate {
    @IBOutlet weak var metalView: MTKView!
    
    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.colorPixelFormat = .rgba16Float
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.delegate = self

        guard metalView.device != nil else {
            print("Metal is not supported on this device")
            return
        }
        
        let scene = Scene.newTestScene(device: metalView.device!)
        
        // Configure the renderer to draw to the view.
        renderer = Renderer(metalDevice: metalView.device!, scene: scene, renderDestination: metalView)
        
        // Schedule the screen to be drawn for the first time.
        renderer.drawRectResized(size: metalView.bounds.size)
        
        addGestureRecognizers(to: view)
    }
    
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
    
    func addGestureRecognizers(to view: NSView) {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(gesture:)))
        view.addGestureRecognizer(pan)
    }
    
    @objc func handlePan(gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        
        let delta = float2(Float(translation.x),
                           Float(translation.y))
      
        renderer.camera.rotate(delta: delta, sensitivity: 0.005)
        
        // This controls the rotation matrix used by the
        // raytracing kernel.
        renderer.delta.x -= Float(translation.x) * 0.005
        renderer.delta.y += Float(translation.y) * 0.005
        
        // print("Delta X:", renderer.delta.x)
        // print("Delta Y:", renderer.delta.y)
        
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    override func scrollWheel(with event: NSEvent) {
        renderer.camera.zoom(delta: Float(event.deltaY))
        renderer.cameraDistance -= Float(event.deltaY) * 0.05
        
        // print("Camera Distance:", renderer.cameraDistance)
    }
    
    @IBAction func switchRenderingMethod(_ sender: NSSegmentedControl) {
        // renderer.useRasterization = (sender.selectedSegment == 0) ? true : false
        
        switch sender.selectedSegment {
        case 0:
            renderer.useRasterization = true
        case 1:
            renderer.useRasterization = false
        default:
            renderer.useRasterization = false
        }
    }
    
    @IBAction func updateNumberOfBounces(_ sender: NSPopUpButton) {
        renderer.raytracingUniforms.bounces = sender.indexOfSelectedItem + 1
        
        if renderer.useAccumulation == true {
            renderer.frameIndex = 0
        }
    }
    
    @IBAction func toggleDenoising(_ sender: NSSwitch) {
    
        switch sender.state {
        case .on:
            renderer.useAccumulation = false
        case .off:
            renderer.useAccumulation = true
        default:
            print("On/Off are the only valid states in this case.")
        }
        
        // This has to be reset also since the accumulation
        // won't be happening when the denoiser is running,
        // which means the images won't match up when you
        // switch back...
        renderer.frameIndex = 0
    }
}
