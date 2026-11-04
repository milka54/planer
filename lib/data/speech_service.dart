import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Диктовка голосом (speech-to-text) для полей ввода.
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final SpeechToText _stt = SpeechToText();
  bool _available = false;
  bool _initialized = false;
  bool _listening = false;
  void Function()? _onStopped;

  bool get isListening => _listening;

  Future<bool> ensureAvailable() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _finishSession();
          }
        },
        onError: (e) {
          debugPrint('speech error: ${e.errorMsg}');
          _finishSession();
        },
      );
    } catch (e) {
      debugPrint('speech init: $e');
      _available = false;
    }
    return _available;
  }

  void _finishSession() {
    if (!_listening) return;
    _listening = false;
    final cb = _onStopped;
    _onStopped = null;
    cb?.call();
  }

  /// Начать диктовку. [onResult] зовётся на каждое распознанное обновление
  /// (текст нарастает; [finalResult] — фраза распознана полностью).
  /// [onStopped] — сессия закончилась (пауза, остановка, ошибка).
  /// Возвращает false, если распознавание недоступно (нет прав/языка).
  Future<bool> start({
    required void Function(String text, bool finalResult) onResult,
    void Function()? onStopped,
  }) async {
    if (_listening) return false;
    if (!await ensureAvailable()) return false;
    _onStopped = onStopped;
    _listening = true;
    try {
      await _stt.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: SpeechListenOptions(
          localeId: 'ru_RU',
          partialResults: true,
          cancelOnError: false,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('speech listen: $e');
      _listening = false;
      _onStopped = null;
      return false;
    }
  }

  Future<void> stop() async {
    if (!_listening) return;
    try {
      await _stt.stop();
    } catch (e) {
      debugPrint('speech stop: $e');
    }
    _finishSession();
  }
}
