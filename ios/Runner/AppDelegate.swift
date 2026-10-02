import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let voiceRecorderChannelName = "field_sales/voice_recorder"

  private var voiceRecorder: AVAudioRecorder?
  private var voiceRecordingURL: URL?
  private var voiceRecordingStartedAt: Date?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let voiceRecorderChannel = FlutterMethodChannel(
      name: Self.voiceRecorderChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    voiceRecorderChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "VOICE_RECORDER_UNAVAILABLE",
            message: "Voice recorder is unavailable.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "requestPermission":
        self.requestMicrophonePermission(result: result)
      case "start":
        self.startVoiceRecording(result: result)
      case "stop":
        self.stopVoiceRecording(result: result)
      case "cancel":
        self.cancelVoiceRecording()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()

    switch session.recordPermission {
    case .granted:
      result(true)
    case .denied:
      result(false)
    case .undetermined:
      session.requestRecordPermission { granted in
        DispatchQueue.main.async {
          result(granted)
        }
      }
    @unknown default:
      result(false)
    }
  }

  private func startVoiceRecording(result: FlutterResult) {
    guard AVAudioSession.sharedInstance().recordPermission == .granted else {
      result(
        FlutterError(
          code: "MIC_PERMISSION_REQUIRED",
          message: "Microphone permission is required.",
          details: nil
        )
      )
      return
    }

    guard voiceRecorder == nil else {
      result(
        FlutterError(
          code: "RECORDING_IN_PROGRESS",
          message: "A voice note is already being recorded.",
          details: nil
        )
      )
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)

      let baseDirectory =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      let folder = baseDirectory.appendingPathComponent(
        "visit_voice_notes",
        isDirectory: true
      )

      try FileManager.default.createDirectory(
        at: folder,
        withIntermediateDirectories: true,
        attributes: nil
      )

      let fileURL = folder.appendingPathComponent(
        "visit-note-\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
      )

      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]

      let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
      guard recorder.prepareToRecord(), recorder.record() else {
        throw NSError(
          domain: "FieldPulseVoiceRecorder",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Could not start audio recording."]
        )
      }

      voiceRecorder = recorder
      voiceRecordingURL = fileURL
      voiceRecordingStartedAt = Date()
      result(fileURL.path)
    } catch {
      releaseVoiceRecorder(deleteFile: true)
      result(
        FlutterError(
          code: "VOICE_RECORDING_START_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func stopVoiceRecording(result: FlutterResult) {
    guard
      let recorder = voiceRecorder,
      let fileURL = voiceRecordingURL,
      let startedAt = voiceRecordingStartedAt
    else {
      result(
        FlutterError(
          code: "NO_RECORDING",
          message: "No voice note recording is active.",
          details: nil
        )
      )
      return
    }

    recorder.stop()

    let durationSeconds = max(
      1,
      Int(Date().timeIntervalSince(startedAt).rounded(.down))
    )

    voiceRecorder = nil
    voiceRecordingURL = nil
    voiceRecordingStartedAt = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(
        FlutterError(
          code: "VOICE_RECORDING_STOP_FAILED",
          message: "The recorded voice note could not be saved.",
          details: nil
        )
      )
      return
    }

    result([
      "path": fileURL.path,
      "duration_seconds": durationSeconds,
    ])
  }

  private func cancelVoiceRecording() {
    releaseVoiceRecorder(deleteFile: true)
  }

  private func releaseVoiceRecorder(deleteFile: Bool) {
    if let recorder = voiceRecorder, recorder.isRecording {
      recorder.stop()
    }

    if deleteFile, let fileURL = voiceRecordingURL {
      try? FileManager.default.removeItem(at: fileURL)
    }

    voiceRecorder = nil
    voiceRecordingURL = nil
    voiceRecordingStartedAt = nil

    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }
}
