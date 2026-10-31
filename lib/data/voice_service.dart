import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Запись и хранение голосовых вложений.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<Directory> _voicesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/voices');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('voice permission: $e');
      return false;
    }
  }

  /// Начать запись. Возвращает true, если запись пошла.
  Future<bool> start() async {
    if (_recording) return false;
    final ok = await hasPermission();
    if (!ok) return false;

    final dir = await _voicesDir();
    final path =
        '${dir.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _currentPath = path;
      _recording = true;
      return true;
    } catch (e) {
      debugPrint('voice start: $e');
      return false;
    }
  }

  /// Остановить запись. Возвращает путь к файлу или null.
  Future<String?> stop() async {
    if (!_recording) return null;
    try {
      final path = await _recorder.stop();
      _recording = false;
      final result = path ?? _currentPath;
      _currentPath = null;
      if (result != null && await File(result).exists()) {
        return result;
      }
      return null;
    } catch (e) {
      debugPrint('voice stop: $e');
      _recording = false;
      _currentPath = null;
      return null;
    }
  }

  Future<void> cancel() async {
    if (!_recording) return;
    try {
      await _recorder.stop();
    } catch (_) {}
    _recording = false;
    final p = _currentPath;
    _currentPath = null;
    if (p != null) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('voice delete: $e');
    }
  }
}
