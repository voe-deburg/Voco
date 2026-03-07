import Testing

@Test func voiceCommandProcessing() {
    let input = "buy groceries comma eggs comma milk period"
    let output = VoiceCommandProcessor.process(input)
    #expect(output.contains(","))
    #expect(output.contains("."))
}

@Test func audioConverterProducesValidWAV() {
    let pcmData = Data(repeating: 0, count: 1600) // 100ms of silence at 16kHz 16-bit
    let wav = AudioConverter.pcmToWAV(pcmData: pcmData)
    // WAV header is 44 bytes
    #expect(wav.count == pcmData.count + 44)
    // Check RIFF header
    let riff = String(data: wav[0..<4], encoding: .ascii)
    #expect(riff == "RIFF")
}
