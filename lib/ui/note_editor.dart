import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';
import '../data/speech_service.dart';
import '../data/storage.dart';
import '../data/voice_service.dart';
import 'reminder_time_picker.dart';
import 'widgets.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? existing;
  final String? sectionId;
  const NoteEditorScreen({super.key, this.existing, this.sectionId});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final List<String> _voicePaths;
  late final List<String> _imagePaths;
  DateTime? _reminder;
  int _colorIndex = 0;
  bool _saving = false;
  bool _recording = false;
  String? _dictating;
  String _dictBuf = '';
  int _recordingSeconds = 0;
  Timer? _recTimer;

  final AudioPlayer _player = AudioPlayer();
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _title = TextEditingController(text: n?.title ?? '');
    _content = TextEditingController(text: n?.content ?? '');
    _voicePaths = [...?n?.voicePaths];
    _imagePaths = [...?n?.imagePaths];
    _reminder = n?.reminderDate;
    _colorIndex = n?.colorIndex ?? 0;
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    VoiceService.instance.cancel();
    _player.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) {
    return showReminderDateTimePicker(
      context,
      initial: initial,
      allowClear: initial != null,
    );
  }

  Future<void> _pickReminder() async {
    final picked = await _pickDateTime(_reminder);
    if (picked != null) setState(() => _reminder = picked);
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await VoiceService.instance.stop();
      _recTimer?.cancel();
      setState(() {
        _recording = false;
        _recordingSeconds = 0;
      });
      if (path != null) {
        setState(() => _voicePaths.add(path));
      }
      return;
    }

    final ok = await VoiceService.instance.start();
    if (!ok) {
      if (mounted) {
        showSnack(context, 'Нет доступа к микрофону');
      }
      return;
    }
    setState(() {
      _recording = true;
      _recordingSeconds = 0;
    });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds++);
    });
  }

  Future<void> _playVoice(String path) async {
    if (_playingPath == path) {
      await _player.stop();
      setState(() => _playingPath = null);
      return;
    }
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      setState(() => _playingPath = path);
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось воспроизвести');
    }
  }

  void _removeVoice(int index) async {
    final path = _voicePaths[index];
    await VoiceService.instance.deleteFile(path);
    setState(() => _voicePaths.removeAt(index));
    if (_playingPath == path) {
      await _player.stop();
      _playingPath = null;
    }
  }

  Widget _micButton(String field, TextEditingController ctrl) {
    final active = _dictating == field;
    return IconButton(
      tooltip: 'Голосовой ввод',
      icon: Icon(
        active ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: active ? AppPalette.rose : null,
      ),
      onPressed: () => _toggleDictation(field, ctrl),
    );
  }

  Future<void> _toggleDictation(String field, TextEditingController ctrl) async {
    if (_dictating == field) {
      await SpeechService.instance.stop();
      if (mounted) setState(() => _dictating = null);
      return;
    }
    await SpeechService.instance.stop();
    _dictBuf = ctrl.text.trim();
    final ok = await SpeechService.instance.start(
      onResult: (text, finalResult) {
        ctrl.text = _dictBuf.isEmpty ? text : '$_dictBuf $text';
        if (finalResult) _dictBuf = ctrl.text;
      },
      onStopped: () {
        if (mounted) setState(() => _dictating = null);
      },
    );
    if (!ok) {
      if (mounted) {
        showSnack(context, 'Голосовой ввод недоступен на этом устройстве');
      }
      return;
    }
    if (mounted) setState(() => _dictating = field);
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final saved =
          await StorageService.instance.persistNoteAttachment(File(picked.path));
      if (saved == null) return;
      setState(() => _imagePaths.add(saved));
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось добавить фото');
    }
  }

  Future<void> _removeImage(String path) async {
    await StorageService.instance.deleteNoteAttachment(path);
    setState(() => _imagePaths.remove(path));
  }

  void _openImage(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(path: path),
      ),
    );
  }

  void _pickPhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Галерея'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _addPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _addPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();

    if (title.isEmpty &&
        content.isEmpty &&
        _voicePaths.isEmpty &&
        _imagePaths.isEmpty) {
      showSnack(context, 'Добавьте заголовок, текст, голос или фото');
      return;
    }
    setState(() => _saving = true);

    if (widget.existing == null) {
      await NotesRepository.instance.create(
        title: title,
        content: content,
        sectionId: widget.sectionId,
        reminderDate: _reminder,
        colorIndex: _colorIndex,
        voicePaths: _voicePaths,
        imagePaths: _imagePaths,
      );
    } else {
      final base = widget.existing!;
      final updated = Note(
        id: base.id,
        title: title,
        content: content,
        createdAt: base.createdAt,
        updatedAt: DateTime.now(),
        reminderDate: _reminder,
        colorIndex: _colorIndex,
        pinned: base.pinned,
        archived: base.archived,
        ownerKey: base.ownerKey,
        sectionId: base.sectionId,
        voicePaths: _voicePaths,
        imagePaths: _imagePaths,
      );
      await NotesRepository.instance.replaceInMemory(updated);
      await NotesRepository.instance.setReminder(updated, _reminder);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        AppPalette.noteColors[_colorIndex % AppPalette.noteColors.length];
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? AppPalette.inkDeep : AppPalette.paper,
      appBar: AppBar(
        title:
            Text(widget.existing == null ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            tooltip: 'Сохранить',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AppPalette.noteColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final selected = i == _colorIndex;
                return GestureDetector(
                  onTap: () => setState(() => _colorIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppPalette.noteColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
              decoration: InputDecoration(
                hintText: 'Заголовок (например: Приём к врачу)',
                filled: false,
                border: InputBorder.none,
                suffixIcon: _micButton('title', _title),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Текст заметки',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.2,
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.white.withOpacity(0.78),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark ? Colors.white12 : Colors.black12,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _content,
              maxLines: 10,
              minLines: 5,
              style: const TextStyle(fontSize: 16, height: 1.4),
              decoration: InputDecoration(
                hintText: 'Напишите заметку…',
                border: InputBorder.none,
                isDense: true,
                suffixIcon: _micButton('content', _content),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Фото-вложения
          Text(
            'Фото',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.2,
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final path in _imagePaths)
                GestureDetector(
                  onTap: () => _openImage(path),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(path),
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 88,
                            height: 88,
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removeImage(path),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Material(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickPhotoSource,
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, color: color),
                        const SizedBox(height: 4),
                        Text(
                          'Фото',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Голосовые вложения
          Text(
            'Голосовые заметки',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: 0.2,
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 10),
          ..._voicePaths.asMap().entries.map((e) {
            final i = e.key;
            final path = e.value;
            final playing = _playingPath == path;
            final exists = File(path).existsSync();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: IconButton(
                    onPressed: exists ? () => _playVoice(path) : null,
                    icon: Icon(
                      playing
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 36,
                      color: AppPalette.accent,
                    ),
                  ),
                  title: Text(
                    'Запись ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    exists ? 'Голосовое вложение' : 'Файл недоступен',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _removeVoice(i),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          // Кнопка записи
          SizedBox(
            height: 56,
            child: Material(
              color: _recording
                  ? AppPalette.rose.withOpacity(0.2)
                  : color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _toggleRecord,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _recording
                          ? Icons.stop_circle_rounded
                          : Icons.mic_rounded,
                      color: _recording ? AppPalette.rose : color,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _recording
                          ? 'Идёт запись · ${_fmtDuration(_recordingSeconds)}'
                          : 'Записать голос',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _recording ? AppPalette.rose : color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: Icon(
                _reminder == null
                    ? Icons.alarm_add_outlined
                    : Icons.alarm_on_rounded,
                color: _reminder == null ? null : AppPalette.accent,
              ),
              title: const Text('Напоминание'),
              subtitle: _reminder == null
                  ? const Text('Необязательно')
                  : Text(formatDateTimeRu(_reminder!)),
              trailing: _reminder == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _reminder = null),
                    ),
              onTap: _pickReminder,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: widget.existing == null ? 'Создать заметку' : 'Сохранить',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
