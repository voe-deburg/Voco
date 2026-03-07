import AVFoundation
import CoreMedia
import SwiftUI

// MARK: - Mic Test

@Observable
@MainActor
final class MicTestService {
    var level: Float = 0
    var isTesting = false
    private var session: AVCaptureSession?
    private var levelBox = AudioLevelBox()
    private var pollTask: Task<Void, Never>?
    private var delegate: MicTestAudioDelegate?

    func start(deviceUID: String) {
        stop()

        let session = AVCaptureSession()

        let device: AVCaptureDevice?
        if deviceUID.isEmpty {
            device = AVCaptureDevice.default(for: .audio)
        } else {
            device = AVCaptureDevice(uniqueID: deviceUID) ?? AVCaptureDevice.default(for: .audio)
        }

        guard let device else {
            print("[Typeless] Mic test: no audio device found")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            print("[Typeless] Mic test input error: \(error)")
            return
        }

        let output = AVCaptureAudioDataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }

        let del = MicTestAudioDelegate(levelBox: levelBox)
        self.delegate = del
        output.setSampleBufferDelegate(del, queue: DispatchQueue(label: "typeless.mic-test"))

        session.startRunning()
        self.session = session
        isTesting = true

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isTesting else { break }
                self.level = self.levelBox.level
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        session?.stopRunning()
        session = nil
        delegate = nil
        isTesting = false
        level = 0
    }
}

private final class MicTestAudioDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let levelBox: AudioLevelBox

    init(levelBox: AudioLevelBox) {
        self.levelBox = levelBox
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let ptr = dataPointer else { return }

        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let asbd = formatDesc.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }

        let rms: Float
        if let asbd, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let count = length / MemoryLayout<Float>.size
            let floats = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
            var sum: Float = 0
            for i in 0..<count { sum += floats[i] * floats[i] }
            rms = sqrt(sum / Float(max(count, 1)))
        } else if let asbd, asbd.mBitsPerChannel == 16 {
            let count = length / MemoryLayout<Int16>.size
            let samples = UnsafeRawPointer(ptr).assumingMemoryBound(to: Int16.self)
            var sum: Float = 0
            for i in 0..<count {
                let s = Float(samples[i]) / Float(Int16.max)
                sum += s * s
            }
            rms = sqrt(sum / Float(max(count, 1)))
        } else {
            return
        }

        levelBox.level = rms
    }
}

// MARK: - STT Settings View

struct STTSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var microphones: [(id: String, name: String)] = []
    @State private var micTest = MicTestService()
    @State private var sttApiKeyInput: String = ""
    @State private var sttKeySaved = false

    private static let sttLanguages: [(code: String, name: String)] = [
        ("en", "English"), ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("ru", "Russian"),
        ("pt", "Portuguese"), ("it", "Italian"), ("ar", "Arabic"), ("hi", "Hindi"),
        ("th", "Thai"), ("vi", "Vietnamese"), ("id", "Indonesian"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Microphone")

            SettingsRow("Input:") {
                Picker("", selection: $settings.selectedMicrophoneID) {
                    Text("System Default").tag("")
                    ForEach(microphones, id: \.id) { mic in
                        Text(mic.name).tag(mic.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            SettingsDescription("Select which microphone to use for recording.")

            HStack(spacing: 12) {
                Button(micTest.isTesting ? "Stop Test" : "Test Microphone") {
                    if micTest.isTesting {
                        micTest.stop()
                    } else {
                        micTest.start(deviceUID: settings.selectedMicrophoneID)
                    }
                }
                .controlSize(.small)

                if micTest.isTesting {
                    MicLevelBar(level: micTest.level)
                        .frame(maxWidth: 200, maxHeight: 8)
                }
            }
            .padding(.top, 8)

            SettingsDivider()

            SectionHeader("STT API")
            SettingsDescription("OpenAI-compatible endpoint (DashScope for Qwen, Groq, OpenAI, etc.)")

            SettingsRow("Base URL:") {
                TextField(AppConstants.defaultSTTBaseURL, text: $settings.sttBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
            }

            SettingsRow("Model:") {
                TextField(AppConstants.defaultSTTModel, text: $settings.sttModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }

            SettingsRow("API Key:") {
                SecureField("sk-...", text: $sttApiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onAppear {
                        sttApiKeyInput = KeychainHelper.load(key: "stt_api_key") ?? ""
                    }
                Button(sttKeySaved ? "Saved" : "Save") {
                    try? KeychainHelper.save(key: "stt_api_key", value: sttApiKeyInput)
                    sttKeySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sttKeySaved = false }
                }
                .disabled(sttApiKeyInput.isEmpty)
                .controlSize(.small)
            }

            SettingsDivider()

            SettingsRow("Language:") {
                Picker("", selection: $settings.inputLanguage) {
                    ForEach(Self.sttLanguages, id: \.code) { lang in
                        Text("\(lang.name) (\(lang.code))").tag(lang.code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            SettingsDescription("Language hint for speech recognition.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            microphones = AudioRecorderService.availableMicrophones()
        }
        .onDisappear {
            micTest.stop()
        }
        .onChange(of: settings.selectedMicrophoneID) {
            if micTest.isTesting {
                micTest.start(deviceUID: settings.selectedMicrophoneID)
            }
        }
    }
}

private struct MicLevelBar: View {
    var level: Float

    private var normalizedLevel: Double {
        min(1.0, Double(level) * 5.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geo.size.width * normalizedLevel)
                    .animation(.linear(duration: 0.05), value: normalizedLevel)
            }
        }
    }

    private var barColor: Color {
        if normalizedLevel > 0.8 { return .red }
        if normalizedLevel > 0.5 { return .yellow }
        return .green
    }
}
