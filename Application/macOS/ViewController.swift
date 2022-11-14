//
//  ViewController.swift
//  MTLRaytracing-macOS
//
//  Created by Eoin Roe on 08/12/2020.
//

import Cocoa
import Metal
import MetalKit
import AVFoundation

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
    
    // var captureInput: AVCaptureScreenInput!
    // var captureSession: AVCaptureSession!
    
    var frameCapture: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.framebufferOnly = false
        metalView.delegate = self

        guard metalView.device != nil else {
            print("Metal is not supported on this device")
            return
        }
        
        // captureSession = AVCaptureSession()
        //
        // captureInput = AVCaptureScreenInput()
        // captureInput.minFrameDuration = CMTimeMake(value: 1, timescale: 40)
        //
        // captureSession.addInput(captureInput)
        
        
        
        
        
        // let device = AVCaptureDevice(uniqueID: <#T##String#>)
        // device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 40)
         
        
        let scene = Scene.newTestScene(device: metalView.device!)
        
        // Configure the renderer to draw to the view.
        renderer = Renderer(metalDevice: metalView.device!, scene: scene, renderDestination: metalView)
        
        // Schedule the screen to be drawn for the first time.
        renderer.drawRectResized(size: metalView.bounds.size)
        
        addGestureRecognizers(to: view)
    }
    
    override func viewDidAppear() {
        print("Start running.")
        // captureSession.startRunning()
    }
    
    override func viewWillDisappear() {
        print("Stop running.")
        // captureSession.stopRunning()
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
        
        // This basically takes a screenshot
        // if frameCapture {
        //     screenShot()
        //     frameCapture = false
        // }
        
        if frameCapture {
            writeFrame(frameCount: renderer.frameCount, view: view)
        }
    }
    
    func writeFrame(frameCount: UInt32, view: MTKView) {
         /*
         
         if let drawable = view.currentDrawable,
            var image = CIImage(mtlTexture: drawable.texture,
                                  options: [:]) {
         */
         
        if var image = CIImage(mtlTexture: renderer.accumulation.read!, options: [:]) {
            image = image.transformed(by: image.orientationTransform(for: .downMirrored))
            
            // Sandboxing enforces strict permsissions on your application meaning that you
            // cannot write to the desktop unless it is switched off.
            let url = URL(fileURLWithPath: "/Users/eoinroe/Desktop/Frames")
            
            let context = CIContext()
            
            /* Render a CIImage to PNG data. Image must have a finite non-empty extent. */
            /* The CGColorSpace must be kCGColorSpaceModelRGB or kCGColorSpaceModelMonochrome */
            /* and must match the specified CIFormat. */
            /* No options keys are supported at this time. */
            
            do {
                try context.writePNGRepresentation(of: image,
                                                   to: url.appendingPathComponent("frame" + String(frameCount) + ".png"),
                                                   format: CIFormat.RGBA16,
                                                   colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                   // colorSpace: kCGColorSpaceModelRGB,
                                                   options: [:])
            } catch let error {
                print("Could not save the png image \(error)")
            }
        }
    }
    
    func screenShot() {
        if var image = CIImage(mtlTexture: renderer.accumulation.read!, options: [:]) {
            image = image.transformed(by: image.orientationTransform(for: .downMirrored))
            
            // Sandboxing enforces strict permsissions on your application meaning that you
            // cannot write to the desktop unless it is switched off.
            let paths = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
            let url = paths[0]
        
            let context = CIContext()
            
            do {
                try context.writeJPEGRepresentation(of: image, to: url.appendingPathComponent("testFromCIImage.jpeg"), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])
            } catch let error {
                print("Could not save the jpeg image \(error)")
            }
            
            do {
                try context.writePNGRepresentation(of: image,
                                                   to: url.appendingPathComponent("testFromCIImage.png"),
                                                   format: CIFormat.RGBA16,
                                                   colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
                                                   options: [:])
            } catch let error {
                print("Could not save the png image \(error)")
            }
        }
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
        
        // Clamp the y-position of the camera
        renderer.delta.y = min(renderer.delta.y + Float(translation.y) * 0.001, 0.0)
        
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
            metalView.colorPixelFormat = .rgba16Float
        case .off:
            renderer.useAccumulation = true
            
            if renderer.useGammaCorrection {
                metalView.colorPixelFormat = .bgra8Unorm
            }
        default:
            print("On/Off are the only valid states in this case.")
        }
        
        // This has to be reset also since the accumulation
        // won't be happening when the denoiser is running,
        // which means the images won't match up when you
        // switch back...
        renderer.frameIndex = 0
    }
    
    @IBAction func toggleGammaCorrection(_ sender: NSSwitch) {
        switch sender.state {
        case .on:
            metalView.colorPixelFormat = .bgra8Unorm
            renderer.useGammaCorrection = true
        case .off:
            metalView.colorPixelFormat = .rgba16Float
            renderer.useGammaCorrection = false
        default:
            print("On/Off are the only valid states in this case.")
        }
    }
    
    @IBAction func choosePixelFormat(_ sender: NSPopUpButton) {
        // metalView.colorPixelFormat = .bgra8Unorm_srgb
    }
    
    @IBAction func captureFrames(_ sender: NSButton) {
        print("Capturing frames.")
        frameCapture = true
        
        // Set this to zero
        renderer.frameCount = 0
        
        let desktopDirectoryURL = try? FileManager.default.url(for: .desktopDirectory,
                                                               in: .userDomainMask,
                                                               appropriateFor: nil,
                                                               create: false)

        // if var url = desktopDirectoryURL {
        //     url.appendPathComponent("Frames")
        // }
        
        guard var url = desktopDirectoryURL else {
            print("The url is not valid.")
            return
        }
        
        url.appendPathComponent("Frames")
        
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("The directory could not be created \(error)")
        }
    }
}
