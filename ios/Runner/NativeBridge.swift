import AVFoundation
import UIKit
import Vision

/// 原生桥：语音（录音 / 播放 MP3）+ OCR（Vision 中文识别）
///
/// 挂载方式：在 AppDelegate.swift 里调用 NativeBridge.register(with: registrar)
/// MethodChannel 名称与 Dart 侧一致：
///   - psc/voice : startRecord / readFrame / stopRecord / playMp3
///   - psc/ocr   : recognize
///
/// 录音采用 AVAudioEngine 实时采集，16k 单声道 PCM16，逐帧缓冲，
/// Dart 侧通过 readFrame 以 40ms（1280 字节）为单位取帧，对齐安卓版流式上行。
class NativeBridge: NSObject {

    // MARK: - 录音状态
    private var audioEngine: AVAudioEngine?
    private var frameBuffer = Data()
    private let bufferLock = NSLock()
    private var recording = false

    private var audioPlayer: AVAudioPlayer?

    static func register(with registrar: FlutterPluginRegistrar) {
        let voiceChannel = FlutterMethodChannel(name: "psc/voice",
                                                binaryMessenger: registrar.messenger())
        let instance = NativeBridge()
        voiceChannel.setMethodCallHandler { call, result in
            instance.handleVoice(call: call, result: result)
        }

        let ocrChannel = FlutterMethodChannel(name: "psc/ocr",
                                              binaryMessenger: registrar.messenger())
        ocrChannel.setMethodCallHandler { call, result in
            instance.handleOcr(call: call, result: result)
        }
    }

    // MARK: - 语音处理
    private func handleVoice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecord":
            startRecord(result: result)
        case "readFrame":
            readFrame(result: result)
        case "stopRecord":
            stopRecord(result: result)
        case "playMp3":
            playMp3(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startRecord(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            session.requestRecordPermission { granted in
                if !granted {
                    result(FlutterError(code: "REC", message: "没有麦克风权限", details: nil))
                    return
                }
            }
        } catch {
            result(FlutterError(code: "REC", message: "麦克风初始化失败", details: nil))
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // 目标：16k 单声道 PCM16。iOS 输入可能是 48k，需用 mixer 或 convert 到 16k。
        // 用 inputNode 的 format 采样，再用 AVAudioConverter 转 16k。
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: false)!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            result(FlutterError(code: "REC", message: "音频转换器初始化失败", details: nil))
            return
        }

        bufferLock.lock()
        frameBuffer.removeAll()
        bufferLock.unlock()
        recording = true

        input.installTap(onBus: 0, bufferSize: 1280, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.recording else { return }
            // 转 16k PCM16
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
            if let channelData = converted.int16ChannelData?[0] {
                let frameLen = Int(converted.frameLength)
                let bytes = Data(bytes: channelData, count: frameLen * 2)
                self.bufferLock.lock()
                self.frameBuffer.append(bytes)
                self.bufferLock.unlock()
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            result(FlutterError(code: "REC", message: "录音启动失败：\(error.localizedDescription)", details: nil))
            return
        }
        audioEngine = engine
        result(1)
    }

    private func readFrame(result: @escaping FlutterResult) {
        bufferLock.lock()
        var data: Data?
        if frameBuffer.count >= 1280 {
            data = frameBuffer.subdata(in: 0..<1280)
            frameBuffer.removeSubrange(0..<1280)
        }
        bufferLock.unlock()
        result(data == nil ? nil : FlutterStandardTypedData(bytes: data!))
    }

    private func stopRecord(result: @escaping FlutterResult) {
        recording = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        result(nil)
    }

    private func playMp3(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let frames = args["frames"] as? [String] else {
            result(nil)
            return
        }
        var allData = Data()
        for f in frames {
            if let d = Data(base64Encoded: f) {
                allData.append(d)
            }
        }
        guard !allData.isEmpty else {
            result(nil)
            return
        }

        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("psc_\(UUID().uuidString).mp3")
        let url = URL(fileURLWithPath: path)
        do {
            try allData.write(to: url)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            // 播放失败静默
        }
        result(nil)
    }

    // MARK: - OCR（Vision 中文识别）
    private func handleOcr(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "recognize" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData else {
            result(nil)
            return
        }
        let data = bytes.data
        guard let image = UIImage(data: data)?.cgImage else {
            result(nil)
            return
        }

        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else {
                result(nil)
                return
            }
            let sorted = observations.sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            let text = sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            result(text)
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                result(nil)
            }
        }
    }
}
