import 'package:flutter/services.dart';

class VisitVoiceRecorder {
  static const MethodChannel _channel = MethodChannel(
    'field_sales/voice_recorder',
  );

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<void> start() async {
    await _channel.invokeMethod<String>('start');
  }

  Future<VisitVoiceRecording> stop() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('stop');

    if (raw == null || raw['path'] == null) {
      throw StateError('The recorded voice note could not be saved.');
    }

    return VisitVoiceRecording(
      path: raw['path'].toString(),
      durationSeconds: (raw['duration_seconds'] as num?)?.toInt() ?? 1,
    );
  }

  Future<void> cancel() async {
    await _channel.invokeMethod<bool>('cancel');
  }
}

class VisitVoiceRecording {
  const VisitVoiceRecording({
    required this.path,
    required this.durationSeconds,
  });

  final String path;
  final int durationSeconds;
}
