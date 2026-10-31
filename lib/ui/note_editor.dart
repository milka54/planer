import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';
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
  DateTime? _reminder;
  int _colorIndex = 0;
  bool _saving = false;
  bool _recording = false;
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

  String _fmtDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();

    if (title.isEmpty && content.isEmpty && _voicePaths.isEmpty) {
      showSnack(context, 'Добавьте заголовок, текст или голос');
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
              decoration: const InputDecoration(
                hintText: 'Заголовок (например: Приём к врачу)',
                filled: false,
                border: InputBorder.none,
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
              decoration: const InputDecoration(
                hintText: 'Напишите заметку…',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
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
