//
//  ViewController.swift
//  MTLRaytracing-iOS
//
//  Created by Eoin Roe on 09/11/2020.
//

import UIKit
import Metal
import MetalKit
import ReplayKit

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    // var depthPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {}

class ViewController: UIViewController, MTKViewDelegate, RPPreviewViewControllerDelegate {
    var renderer: Renderer!
    
    static var previousScale: CGFloat = 1
    
    /// Device for screen recording
    let recorder = RPScreenRecorder.shared()
    private var isRecording = false
    
    var x: Float = 1
    var y: Float = 1
    let easing: Float = 0.05

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        // Set the view to use the default device.
        if let view = self.view as? MTKView {
            view.device = MTLCreateSystemDefaultDevice()
            view.backgroundColor = UIColor.clear
            view.colorPixelFormat = .bgra8Unorm
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
            
            let scene = Scene.newTestScene(device: view.device!)
            
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
    
    // https://www.hackingwithswift.com/example-code/media/how-to-record-user-videos-using-replaykit
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        dismiss(animated: true)
    }
    
    func startRecording() {
        guard recorder.isAvailable else {
            print("Recording is not available at this time")
            return
        }
    
        recorder.isMicrophoneEnabled = true
    
        // This function has a handler
        recorder.startRecording{ [unowned self] (error) in
    
            guard error == nil else {
                print("There was an error starting the recording.")
                return
            }
    
            print("Started Recording Successfully")
            self.isRecording = true
        }
    }
    
    func stopRecording() {
        recorder.stopRecording { [unowned self] (preview, error) in
            print("Stopped recording")
    
            // The stopRecording function creates a preview controller which we can call in the handler
            guard preview != nil else {
                print("Preview controller is not available.")
                return
            }
    
            let alert = UIAlertController(title: "Recording Finished", message: "Would you like to edit or delete your recording?", preferredStyle: .alert)
    
            let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { (UIAlertAction) in
                self.recorder.discardRecording { () -> Void in
                    print("Recording successfully deleted.")
                }
            }
    
            // If tapped, this action will open up the preview controller so you can watch the recording, save it or edit it
            let editAction = UIAlertAction(title: "edit", style: .default) { (UIAlertAction) -> Void in
                preview?.previewControllerDelegate = self
                self.present(preview!, animated: true, completion: nil)
            }
    
            alert.addAction(editAction)
            alert.addAction(deleteAction)
    
            self.present(alert, animated: true, completion: nil)
            self.isRecording = false
        }
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
    
    // @objc func handleTap(gesture: UITapGestureRecognizer) {
    //     renderer.useAccumulation = !renderer.useAccumulation
    //
    //     // This has to be reset also since the accumulation
    //     // won't be happening when the denoiser is running,
    //     // which means the images won't match up when you
    //     // switch back...
    //     renderer.frameIndex = 0
    // }
    
    @objc func handleTap(gesture: UITapGestureRecognizer) {
        renderer.useGammaCorrection = !renderer.useGammaCorrection
        
        if let view = self.view as? MTKView {
            if renderer.useGammaCorrection {
                view.colorPixelFormat = .bgra8Unorm
            } else {
                view.colorPixelFormat = .rgba16Float
            }
        }
    }
    
    // MARK: - Debug view
    
    // @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
    //     if (sender.state == UIGestureRecognizer.State.began) {
    //         print("Long Press")
    //
    //         renderer.useRasterization = !renderer.useRasterization
    //     }
    // }

    /// Start or stop recording the screen with this gesture
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
        if (sender.state == UIGestureRecognizer.State.began) {
            print("Long Press")
            
            if !isRecording {
                startRecording()
            } else {
                stopRecording()
            }
        }
    }
    
    // MARK: - Camera controls
    
    /*
     The solution is to use a UILongPressGestureRecognizer with minimumPressDuration set to 0.
     With this configuration, it will begin recognizing immediately on touch down, allowing you
     to take action even before the user has moved their finger (or pencil).
          
     https://news.ycombinator.com/item?id=18429780
     https://p5js.org/examples/input-easing.html
     https://medium.com/@aatish.rajkarnikar/how-to-achieve-smooth-uislider-dragging-experience-in-ios-88da67759714
     */
    
    @objc func handlePan(gesture: UIPanGestureRecognizer) {
        // let currentPoint = gesture.location(in: view)
        let translation = gesture.translation(in: gesture.view)
        
        let delta = float2(Float(translation.x),
                           Float(translation.y))
      
        renderer.camera.rotate(delta: delta, sensitivity: 0.001)
        
        // let dx = -Float(translation.x) * 0.001
        // renderer.delta.x += dx * easing
        
        // let dy = Float(translation.y) * 0.001
        // renderer.delta.y += dy * easing
        
        // This controls the rotation matrix used by the
        // raytracing kernel.
        renderer.delta.x -= Float(translation.x) * 0.001
        
        // Clamp the y-position of the camera
        renderer.delta.y = min(renderer.delta.y + Float(translation.y) * 0.001, 0.0)
        
        // Reset
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
        let sensitivity: Float = 50
        let delta = Float(gesture.scale - ViewController.previousScale) * sensitivity
        
        renderer.camera.zoom(delta: delta)
        renderer.cameraDistance -= delta * 0.05
        
        ViewController.previousScale = gesture.scale
        
        if gesture.state == .ended {
            ViewController.previousScale = 1
        }
    }
}
