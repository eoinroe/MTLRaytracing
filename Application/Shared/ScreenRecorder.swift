import AVFoundation

class ScreenRecorder {
    var frameCount: CMTimeValue = 0
    
    var assetWriter: AVAssetWriter?
    
    var sceneInput: AVAssetWriterInput!
    var sceneInputAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    
    func render() {
        
        
        if sceneInput.isReadyForMoreMediaData, let pool = sceneInputAdaptor.pixelBufferPool {
            
            let sceneBuffer = pixelBuffer(pool: pool)
            sceneInputAdaptor.append(sceneBuffer, withPresentationTime: CMTime(value: frameCount, timescale: 60))
        }
        
        
    }
    
    func pixelBuffer(pool: CVPixelBufferPool) -> CVPixelBuffer {
        var pixelBufferOut: CVPixelBuffer?
        
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
        
        if status != kCVReturnSuccess {
            fatalError("CVPixelBufferPoolCreatePixelBuffer() failed")
        }
        
        let pixelBuffer = pixelBufferOut!
        
        return pixelBuffer
    }
}
