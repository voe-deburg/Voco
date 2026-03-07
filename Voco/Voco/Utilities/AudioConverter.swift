import Foundation
import AVFoundation

enum AudioConverter {
    static func pcmToWAV(pcmData: Data, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        var wavData = Data()

        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(littleEndian: fileSize)
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(littleEndian: UInt32(16)) // chunk size
        wavData.append(littleEndian: UInt16(1))  // PCM format
        wavData.append(littleEndian: UInt16(channels))
        wavData.append(littleEndian: UInt32(sampleRate))
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        wavData.append(littleEndian: byteRate)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        wavData.append(littleEndian: blockAlign)
        wavData.append(littleEndian: UInt16(bitsPerSample))

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(littleEndian: dataSize)
        wavData.append(pcmData)

        return wavData
    }
}

extension Data {
    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }

    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
}
