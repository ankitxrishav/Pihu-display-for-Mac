import Foundation
import VideoToolbox
import CoreMedia

class Encoder {
    private var compressionSession: VTCompressionSession?
    private let onEncodedFrame: (Data) -> Void
    
    init(onEncodedFrame: @escaping (Data) -> Void) {
        self.onEncodedFrame = onEncodedFrame
    }
    
    func setupSession(width: Int32, height: Int32) -> Bool {
        if compressionSession != nil {
            teardownSession()
        }
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refCon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
                guard status == noErr, let sampleBuffer = sampleBuffer else {
                    print("[Encoder] Encode frame failed: \(status)")
                    return
                }
                
                let encoder = Unmanaged<Encoder>.fromOpaque(refCon!).takeUnretainedValue()
                encoder.processEncodedFrame(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            print("[Encoder] Failed to create compression session: \(status)")
            return false
        }
        
        // Configure low-latency real-time properties
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber) // Disable B-frames
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 60 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 8_000_000 as CFNumber) // 8 Mbps
        
        // Insert a keyframe every 60 frames (1 second at 60 FPS) to ensure quick recovery on reconnect
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 60 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[Encoder] Setup session for \(width)x\(height)")
        return true
    }
    
    func teardownSession() {
        guard let session = compressionSession else { return }
        VTCompressionSessionInvalidate(session)
        compressionSession = nil
        print("[Encoder] Teardown session")
    }
    
    func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime) {
        guard let session = compressionSession else { return }
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if status != noErr {
            print("[Encoder] VTCompressionSessionEncodeFrame failed: \(status)")
        }
    }
    
    private func processEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        // Check if this is a keyframe
        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [CFDictionary],
           !attachments.isEmpty {
            let dict = attachments[0]
            let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DependsOnOthers).toOpaque()
            if let dependsOnOthers = CFDictionaryGetValue(dict, key) {
                let boolVal = Unmanaged<CFBoolean>.fromOpaque(dependsOnOthers).takeUnretainedValue()
                isKeyframe = (CFBooleanGetValue(boolVal) == false)
            } else {
                isKeyframe = true
            }
        }
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        var packetData = Data()
        
        // 1. If keyframe, prepend SPS and PPS
        if isKeyframe {
            var parameterSetCount = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &parameterSetCount,
                nalUnitHeaderLengthOut: nil
            )
            
            for i in 0..<parameterSetCount {
                var paramSetPointer: UnsafePointer<UInt8>? = nil
                var paramSetSize = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: i,
                    parameterSetPointerOut: &paramSetPointer,
                    parameterSetSizeOut: &paramSetSize,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                if status == noErr, let paramSetPointer = paramSetPointer {
                    packetData.append(contentsOf: [0, 0, 0, 1]) // Start code
                    packetData.append(paramSetPointer, count: paramSetSize)
                }
            }
        }
        
        // 2. Append NAL units from CMSampleBuffer's block buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            if !packetData.isEmpty {
                onEncodedFrame(packetData)
            }
            return
        }
        
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>? = nil
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
            if !packetData.isEmpty {
                onEncodedFrame(packetData)
            }
            return
        }
        
        var offset = 0
        let uint8Pointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: UInt8.self)
        
        while offset < totalLength - 4 {
            // Read 4-byte big-endian length
            let lengthBytes = uint8Pointer + offset
            let nalUnitLength = Int(CFSwapInt32BigToHost(
                UnsafeRawPointer(lengthBytes).assumingMemoryBound(to: UInt32.self).pointee
            ))
            
            if nalUnitLength <= 0 || offset + 4 + nalUnitLength > totalLength {
                break
            }
            
            // Convert length prefix to Annex-B start code
            packetData.append(contentsOf: [0, 0, 0, 1])
            packetData.append(uint8Pointer + offset + 4, count: nalUnitLength)
            
            offset += 4 + nalUnitLength
        }
        
        if !packetData.isEmpty {
            onEncodedFrame(packetData)
        }
    }
}
