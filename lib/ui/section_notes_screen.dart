import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';
import 'multi_select_bar.dart';
import 'note_detail.dart';
import 'note_editor.dart';
import 'widgets.dart';

/// Экран заметок внутри раздела (или «Без раздела»).
class SectionNotesScreen extends StatefulWidget {
  final NoteSection? section;
  final Note? initialNote;

  const SectionNotesScreen({
    super.key,
    required this.section,
    this.initialNote,
  });

  @override
  State<SectionNotesScreen> createState() => _SectionNotesScreenState();
}

class _SectionNotesScreenState extends State<SectionNotesScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _enterSelect(String noteId) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      _selected.add(noteId);
    });
    notesSelectActive.value = true;
  }

  void _toggle(String noteId) {
    setState(() {
      if (_selected.contains(noteId)) {
        _selected.remove(noteId);
        if (_selected.isEmpty) {
          _selectMode = false;
          notesSelectActive.value = false;
        }
      } else {
        _selected.add(noteId);
      }
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    notesSelectActive.value = false;
  }

  List<Note> _selectedNotes(List<Note> all) =>
      all.where((n) => _selected.contains(n.id)).toList();

  Future<void> _moveSelected(List<Note> all) async {
    final target = await showMoveToSectionPicker(context);
    if (target == null || target == moveCancelled) return;
    for (final n in _selectedNotes(all)) {
      await NotesRepository.instance.moveToSection(
        n,
        target.isEmpty ? null : target,
      );
    }
    _exitSelect();
    if (mounted) setState(() {});
  }

  Future<void> _archiveSelected(List<Note> all) async {
    await archiveNotes(_selectedNotes(all), archived: true);
    _exitSelect();
    if (mounted) setState(() {});
  }

  Future<void> _deleteSelected(List<Note> all) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Удалить $count ${count == 1 ? 'заметку' : 'заметок'}?'),
        content: const Text('Действие нельзя отменить.'),
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
    if (ok != true) return;
    for (final n in _selectedNotes(all)) {
      await NotesRepository.instance.delete(n);
    }
    _exitSelect();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialNote != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNote(widget.initialNote!);
      });
    }
  }

  Future<void> _openNote(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openEditor({Note? existing}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          existing: existing,
          sectionId: widget.section?.id,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    notesSelectActive.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final section = widget.section;
    final color = section == null
        ? AppPalette.sky
        : AppPalette
            .noteColors[section.colorIndex % AppPalette.noteColors.length];
    final title = section?.title ?? 'Без раздела';

    return Scaffold(
      backgroundColor: dark ? AppPalette.inkDeep : AppPalette.paper,
      appBar: AppBar(
        title: Text(title),
      ),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: AppPalette.accent,
              foregroundColor: AppPalette.inkDeep,
              icon: const Icon(Icons.edit_rounded),
              label: const Text(
                'Новая',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: ValueListenableBuilder<List<Note>>(
        valueListenable: NotesRepository.instance.notes,
        builder: (context, _, __) {
          final notes = NotesRepository.instance.notesIn(section?.id);
          if (notes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.note_add_outlined,
                        size: 40,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Заметок пока нет',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Нажмите «Новая», чтобы добавить заметку с текстом,\nнапоминанием или голосовым вложением',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            physics: const BouncingScrollPhysics(),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final n = notes[i];
              return StaggeredFadeIn(
                index: i,
                child: _NoteCard(
                  note: n,
                  selected: _selected.contains(n.id),
                  selectMode: _selectMode,
                  onTap: () {
                    if (_selectMode) {
                      _toggle(n.id);
                    } else {
                      _openNote(n);
                    }
                  },
                  onLongPress: () {
                    if (_selectMode) {
                      _toggle(n.id);
                    } else {
                      _enterSelect(n.id);
                    }
                  },
                  onEdit: () => _openEditor(existing: n),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _selectMode
          ? NoteMultiSelectBar(
              count: _selected.length,
              onMoveToSection: () =>
                  _moveSelected(NotesRepository.instance.notesIn(widget.section?.id)),
              onArchive: () =>
                  _archiveSelected(NotesRepository.instance.notesIn(widget.section?.id)),
              onDelete: () =>
                  _deleteSelected(NotesRepository.instance.notesIn(widget.section?.id)),
              onClear: _exitSelect,
            )
          : null,
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectMode;

  const _NoteCard({
    required this.note,
    required this.onTap,
    required this.onEdit,
    this.onLongPress,
    this.selected = false,
    this.selectMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        AppPalette.noteColors[note.colorIndex % AppPalette.noteColors.length];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? Colors.white : AppPalette.inkDeep;
    final muted = textColor.withOpacity(0.72);

    return Material(
      color: selected
          ? AppPalette.accent.withOpacity(0.18)
          : dark ? const Color(0xFF1E2F52) : AppPalette.paperCard,
      borderRadius: BorderRadius.circular(22),
      child: !selectMode
          ? Dismissible(
        key: ValueKey(note.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: AppPalette.rose.withOpacity(0.9),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
        ),
        confirmDismiss: (_) async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text('Удалить заметку?'),
              content: const Text('Действие нельзя отменить.'),
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
          if (ok == true) {
            await NotesRepository.instance.delete(note);
            return true;
          }
          return false;
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: onLongPress ?? onEdit,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withOpacity(0.45), width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(dark ? 0.18 : 0.15),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 7,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(22),
                        bottomLeft: Radius.circular(22),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (note.pinned)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 3, right: 6),
                                  child: Icon(
                                    Icons.push_pin_rounded,
                                    size: 16,
                                    color: color,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  note.title.isEmpty
                                      ? 'Без названия'
                                      : note.title,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    height: 1.2,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (note.preview.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              note.preview,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: muted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (note.hasVoice)
                                NoteChip(
                                  icon: Icons.mic_rounded,
                                  label:
                                      '${note.voicePaths.length} голос.',
                                  color: AppPalette.violet,
                                  filled: true,
                                ),
                              if (note.hasReminder)
                                NoteChip(
                                  icon: Icons.alarm_on_rounded,
                                  label:
                                      formatDateTimeRu(note.reminderDate!),
                                  color: AppPalette.accent,
                                  filled: true,
                                ),
                              NoteChip(
                                icon: Icons.schedule_rounded,
                                label: formatRelative(note.updatedAt),
                                color: color,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
      : InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? AppPalette.accent : color.withOpacity(0.45),
                width: selected ? 2 : 1.3,
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (_) => onTap(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Без названия' : note.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
