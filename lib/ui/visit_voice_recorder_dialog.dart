import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../state/visit_controller.dart';

class VisitVoiceRecorderDialog extends StatefulWidget {
  const VisitVoiceRecorderDialog({super.key, required this.visit});
  final Map<String, dynamic> visit;
  @override
  State<VisitVoiceRecorderDialog> createState() =>
      _VisitVoiceRecorderDialogState();
}

class _VisitVoiceRecorderDialogState extends State<VisitVoiceRecorderDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;
  bool _recording = false;
  String? _error;
  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission is required.');
      return;
    }
    final dir = Directory(
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'visit_voice_notes',
      ),
    );
    await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      'voice_${DateTime.now().microsecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: path,
    );
    setState(() {
      _recording = true;
      _startedAt = DateTime.now();
      _error = null;
    });
  }

  Future<void> _stopAndSave() async {
    final path = await _recorder.stop();
    final started = _startedAt;
    if (path == null || started == null) {
      setState(() => _error = 'Recording could not be saved.');
      return;
    }
    final duration = DateTime.now()
        .difference(started)
        .inSeconds
        .clamp(1, 3600)
        .toInt();
    if (!mounted) return;
    await context.read<VisitController>().attachVoiceNote(
      widget.visit,
      localPath: path,
      durationSeconds: duration,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Visit voice note'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _recording ? Icons.mic : Icons.mic_none,
          size: 54,
          color: _recording ? Theme.of(context).colorScheme.error : null,
        ),
        const SizedBox(height: 12),
        Text(
          _recording ? 'Recording… tap Save when finished.' : 'Record a short visit note. It stays on the device until it can sync.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () async {
          if (_recording) await _recorder.cancel();
          if (context.mounted) Navigator.pop(context, false);
        },
        child: const Text('Cancel'),
      ),
      if (!_recording)
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.mic),
          label: const Text('Record'),
        )
      else
        FilledButton.icon(
          onPressed: _stopAndSave,
          icon: const Icon(Icons.stop),
          label: const Text('Save'),
        ),
    ],
  );
}
