import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

@Observable
@MainActor
final class AudioRecorderService {
    private(set) var isRecording = false
    private(set) var audioLevel: Float = 0

    private var captureSession: AVCaptureSession?
    private var captureDelegate: AudioCaptureDelegate?
    private let levelBox = AudioLevelBox()
    private var levelTimer: Timer?

    /// List available input audio devices
    static func availableMicrophones() -> [(id: String, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        var result: [(id: String, name: String)] = []
        for deviceID in deviceIDs {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr else {
                continue
            }
            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else {
                continue
            }
            let channelCount = UnsafeMutableAudioBufferListPointer(bufferListPtr).reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channelCount > 0 else { continue }

            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid) == noErr else {
                continue
            }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name) == noErr else {
                continue
            }

            result.append((id: uid as String, name: name as String))
        }
        return result
    }

    func startRecording() throws {
        let session = AVCaptureSession()

        let selectedID = AppSettings.shared.selectedMicrophoneID
        let device: AVCaptureDevice?
        if selectedID.isEmpty {
            device = AVCaptureDevice.default(for: .audio)
        } else {
            device = AVCaptureDevice(uniqueID: selectedID) ?? AVCaptureDevice.default(for: .audio)
        }

        guard let device else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio input device found"])
        }
        print("[Typeless] Recording with device: \(device.localizedName)")

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "AudioRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio input"])
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else {
            throw NSError(domain: "AudioRecorder", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output"])
        }
        session.addOutput(output)

        let delegate = AudioCaptureDelegate(levelBox: levelBox)
        self.captureDelegate = delegate
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "typeless.audio-capture"))

        session.startRunning()
        self.captureSession = session
        isRecording = true

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.audioLevel = self.levelBox.level
            }
        }
    }

    /// Stop recording and return WAV data at 16kHz mono 16-bit (for API upload).
    func stopRecording() -> Data {
        levelTimer?.invalidate()
        levelTimer = nil

        captureSession?.stopRunning()
        captureSession = nil
        isRecording = false
        audioLevel = 0

        guard let delegate = captureDelegate else { return Data() }
        captureDelegate = nil

        return delegate.convertToWAV()
    }

    /// Set the input device on an AVAudioEngine by device UID (used by mic test).
    @discardableResult
    nonisolated static func setInputDevice(engine: AVAudioEngine, uid: String) -> Double {
        let deviceID = findDeviceID(uid: uid)

        guard deviceID != 0 else {
            print("[Typeless] Microphone with UID \(uid) not found, using default")
            return 0
        }

        guard let audioUnit = engine.inputNode.audioUnit else {
            print("[Typeless] No audio unit available on input node")
            return 0
        }
        var inputDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &inputDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("[Typeless] Failed to set input device: \(status)")
        }

        let rate = deviceNominalSampleRate(deviceID)
        print("[Typeless] Device nominal sample rate: \(rate) Hz")
        return rate
    }

    nonisolated static func findDeviceID(uid: String) -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return 0 }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return 0 }

        for id in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &cfUID) == noErr else {
                continue
            }
            if (cfUID as String) == uid {
                return id
            }
        }
        return 0
    }

    nonisolated static func deviceNominalSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var sampleRate: Float64 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return sampleRate
    }
}

// MARK: - Audio capture delegate (runs on background queue, thread-safe)

private final class AudioCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let levelBox: AudioLevelBox
    private var samples = [Float]()
    private var sampleRate: Double = 0
    private var channelCount: Int = 1
    private let lock = NSLock()

    init(levelBox: AudioLevelBox) {
        self.levelBox = levelBox
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset = 0
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let ptr = dataPointer else { return }

        // Get format info
        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let asbd = formatDesc.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }

        if sampleRate == 0, let asbd {
            sampleRate = asbd.mSampleRate
            channelCount = max(1, Int(asbd.mChannelsPerFrame))
            print("[Typeless] Capture format: \(sampleRate) Hz, \(asbd.mBitsPerChannel) bit, \(channelCount) ch, float=\(asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0)")
        }

        // Extract Float32 mono samples and calculate RMS
        let isFloat = asbd.map { $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 } ?? false
        let bitsPerChannel = asbd.map { Int($0.mBitsPerChannel) } ?? 32
        let chCount = max(1, asbd.map { Int($0.mChannelsPerFrame) } ?? 1)

        var monoFloats: [Float]
        var rmsSum: Float = 0

        if isFloat && bitsPerChannel == 32 {
            let count = length / MemoryLayout<Float>.size
            let floats = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
            // Take first channel only for mono
            let monoCount = count / chCount
            monoFloats = [Float](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                let s = floats[i * chCount]
                monoFloats[i] = s
                rmsSum += s * s
            }
            let rms = sqrt(rmsSum / Float(max(monoCount, 1)))
            levelBox.level = rms
        } else if bitsPerChannel == 16 {
            let count = length / MemoryLayout<Int16>.size
            let shorts = UnsafeRawPointer(ptr).assumingMemoryBound(to: Int16.self)
            let monoCount = count / chCount
            monoFloats = [Float](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                let s = Float(shorts[i * chCount]) / Float(Int16.max)
                monoFloats[i] = s
                rmsSum += s * s
            }
            let rms = sqrt(rmsSum / Float(max(monoCount, 1)))
            levelBox.level = rms
        } else {
            return
        }

        lock.lock()
        samples.append(contentsOf: monoFloats)
        lock.unlock()
    }

    /// Convert accumulated samples to 16kHz mono 16-bit WAV.
    func convertToWAV() -> Data {
        lock.lock()
        let rawSamples = samples
        samples = []
        lock.unlock()

        guard !rawSamples.isEmpty, sampleRate > 0 else {
            print("[Typeless] No audio samples captured")
            return Data()
        }

        print("[Typeless] Captured \(rawSamples.count) samples at \(sampleRate) Hz (\(Double(rawSamples.count) / sampleRate)s)")

        // Resample to 16kHz using linear interpolation
        let targetRate = AppConstants.sampleRate
        let ratio = targetRate / sampleRate
        let targetCount = Int(Double(rawSamples.count) * ratio)

        guard targetCount > 0 else { return Data() }

        var pcmData = Data(capacity: targetCount * 2)
        for i in 0..<targetCount {
            let srcPos = Double(i) / ratio
            let srcIdx = Int(srcPos)
            let frac = Float(srcPos - Double(srcIdx))

            let s0 = rawSamples[min(srcIdx, rawSamples.count - 1)]
            let s1 = rawSamples[min(srcIdx + 1, rawSamples.count - 1)]
            let interpolated = s0 + frac * (s1 - s0)

            let clamped = max(-1.0, min(1.0, interpolated))
            var sample = Int16(clamped * Float(Int16.max))
            pcmData.append(Data(bytes: &sample, count: 2))
        }

        let wavData = AudioConverter.pcmToWAV(pcmData: pcmData)
        print("[Typeless] WAV data: \(wavData.count) bytes (\(Double(targetCount) / targetRate)s at 16kHz)")
        return wavData
    }
}
