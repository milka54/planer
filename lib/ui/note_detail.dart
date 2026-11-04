import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';
import 'note_editor.dart';
import 'widgets.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  const NoteDetailScreen({super.key, required this.note});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingPath = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
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
    } catch (_) {
      if (mounted) showSnack(context, 'Не удалось воспроизвести');
    }
  }

  void _openImage(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(path: path),
      ),
    );
  }

  Future<void> _pickSection(BuildContext context, Note note) async {
    final sections = NotesRepository.instance.allSections;
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Перенести в раздел',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Разделов пока нет'),
              )
            else ...[
              if (note.sectionId != null)
                ListTile(
                  leading: const Icon(Icons.inbox_rounded),
                  title: const Text('На главный экран'),
                  subtitle: const Text('Без раздела'),
                  onTap: () => Navigator.pop(ctx, ''),
                ),
              for (final s in sections)
                ListTile(
                  leading: Icon(
                    Icons.folder_rounded,
                    color: AppPalette
                        .noteColors[s.colorIndex % AppPalette.noteColors.length],
                  ),
                  title: Text(s.title),
                  trailing: note.sectionId == s.id
                      ? Icon(Icons.check_rounded, color: AppPalette.accent)
                      : null,
                  onTap: () => Navigator.pop(ctx, s.id),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null) return;
    final target = selected.isEmpty ? null : selected;
    if (target == note.sectionId) return;
    await NotesRepository.instance.moveToSection(note, target);
    if (context.mounted) {
      final name = target == null
          ? 'главный экран'
          : (NotesRepository.instance.sectionById(target)?.title ?? 'раздел');
      showSnack(context, 'Перенесено в «$name»');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final color =
        AppPalette.noteColors[note.colorIndex % AppPalette.noteColors.length];
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? AppPalette.inkDeep : AppPalette.paper,
      appBar: AppBar(
        title: const Text('Заметка'),
        actions: [
          IconButton(
            tooltip: 'Копировать текст',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: note.content));
              if (context.mounted) showSnack(context, 'Скопировано');
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: 'Редактировать',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NoteEditorScreen(existing: note),
                ),
              );
              if (context.mounted) setState(() {});
            },
            icon: const Icon(Icons.edit_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'pin') {
                await NotesRepository.instance.togglePin(note);
                if (context.mounted) {
                  showSnack(
                    context,
                    note.pinned ? 'Откреплено' : 'Закреплено',
                  );
                }
              } else if (v == 'archive') {
                await NotesRepository.instance.toggleArchive(note);
                if (context.mounted) {
                  showSnack(
                    context,
                    note.archived ? 'Возвращено из архива' : 'В архив',
                  );
                }
              } else if (v == 'move') {
                await _pickSection(context, note);
              } else if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    title: const Text('Удалить заметку?'),
                    content: const Text('Напоминание будет отменено.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Отмена'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await NotesRepository.instance.delete(note);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(note.pinned ? 'Открепить' : 'Закрепить'),
              ),
              const PopupMenuItem(
                value: 'move',
                child: Text('Перенести в раздел'),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: Text('В архив / из архива'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child:
                    Text('Удалить', style: TextStyle(color: AppPalette.rose)),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(0.18),
                  color.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.4), width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title.isEmpty ? 'Без названия' : note.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 14),
                LinkifiedText(
                  note.content.isEmpty ? 'Пустая заметка' : note.content,
                  style: const TextStyle(fontSize: 17, height: 1.55),
                ),
              ],
            ),
          ),
          if (note.hasImages) ...[
            const SizedBox(height: 18),
            const SectionTitle('ФОТО'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final path in note.imagePaths)
                  GestureDetector(
                    onTap: () => _openImage(path),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(path),
                        width: 108,
                        height: 108,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 108,
                          height: 108,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (note.hasVoice) ...[
            const SizedBox(height: 18),
            const SectionTitle('ГОЛОСОВЫЕ ЗАМЕТКИ'),
            ...note.voicePaths.asMap().entries.map((e) {
              final i = e.key;
              final path = e.value;
              final playing = _playingPath == path;
              final exists = File(path).existsSync();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassPanel(
                  glow: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              );
            }),
          ],
          if (note.hasReminder) ...[
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: GlassPanel(
                glow: true,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppPalette.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: PulseIcon(
                        icon: Icons.alarm_on_rounded,
                        color: AppPalette.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Напоминание',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatDateTimeRu(note.reminderDate!),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          GlassPanel(
            glow: false,
            child: Column(
              children: [
                _MetaRow(
                  icon: Icons.schedule_rounded,
                  label: 'Создано',
                  value: formatDateTimeRu(note.createdAt),
                ),
                const Divider(height: 16),
                _MetaRow(
                  icon: Icons.update_rounded,
                  label: 'Изменено',
                  value: formatDateTimeRu(note.updatedAt),
                ),
                if (note.pinned) ...[
                  const Divider(height: 16),
                  _MetaRow(
                    icon: Icons.push_pin_rounded,
                    label: 'Статус',
                    value: 'Закреплено',
                    valueColor: AppPalette.accent,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = (dark ? Colors.white : Colors.black).withOpacity(0.55);
    return Row(
      children: [
        Icon(icon, size: 18, color: valueColor ?? muted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: muted)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
