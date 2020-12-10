/*
See licenses folder for this class's licensing information.

Abstract:

*/

import Foundation
import simd

class Camera: Node {
  var fovDegrees: Float = 70
    
  var fovRadians: Float {
    return fovDegrees.degreesToRadians
  }

    
  // This is correct for this application since the window size is 500 x 500
  // but need to be careful this isn't causing issues in other applications...
  var aspect: Float = 1
  var near: Float = 0.1
  var far: Float = 1000
  
  var projectionMatrix: float4x4 {
    return float4x4(projectionFov: fovRadians,
                    near: near,
                    far: far,
                    aspect: aspect)
  }
  
  var viewMatrix: float4x4 {
    let translateMatrix = float4x4(translation: position)
    let rotateMatrix = float4x4(rotation: rotation)
    let scaleMatrix = float4x4(scaling: scale)
    return (translateMatrix * scaleMatrix * rotateMatrix).inverse
  }
  
  func zoom(delta: Float) {}
  func rotate(delta: float2, sensitivity: Float) {}
}


class ArcballCamera: Camera {
  // Definitely might want to play with minDistance
  var minDistance: Float = 0.5
  var maxDistance: Float = 10
    
  var target: float3 = [0, 0, 0] {
    didSet {
      _viewMatrix = updateViewMatrix()
    }
  }
  
  var distance: Float = 0 {
    didSet {
      _viewMatrix = updateViewMatrix()
    }
  }
      
  override var rotation: float3 {
    didSet {
      _viewMatrix = updateViewMatrix()
    }
  }
  
  override var viewMatrix: float4x4 {
    return _viewMatrix
  }
    
  private var _viewMatrix = float4x4.identity()
  
  override init() {
    super.init()
    _viewMatrix = updateViewMatrix()
  }
  
  private func updateViewMatrix() -> float4x4 {
    let translateMatrix = float4x4(translation: [target.x, target.y, target.z - distance])
    let rotateMatrix = float4x4(rotationYXZ: [-rotation.x,
                                              rotation.y,
                                              0])
    let matrix = (rotateMatrix * translateMatrix).inverse
    position = rotateMatrix.upperLeft * -matrix.columns.3.xyz
    return matrix
  }
  
  override func zoom(delta: Float) {
    let sensitivity: Float = 0.05
    distance -= delta * sensitivity
    _viewMatrix = updateViewMatrix()
  }
  
  override func rotate(delta: float2, sensitivity: Float) {
      // let sensitivity: Float = 0.001
      
      var x = rotation.x + delta.y * sensitivity
      x = max(-Float.pi/2, min((x), Float.pi/2))
      
      let y = rotation.y + delta.x * sensitivity
  
      // Need to assign the whole [x, y, z] float3 value to the rotation at one time
      rotation = [x, y, 0]
      _viewMatrix = updateViewMatrix()
  }
}
