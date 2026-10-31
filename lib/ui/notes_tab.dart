import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';
import 'archive_screen.dart';
import 'multi_select_bar.dart';
import 'note_detail.dart';
import 'note_editor.dart';
import 'section_notes_screen.dart';
import 'widgets.dart';

/// Действия для FAB в HomeShell: создать заметку или раздел.

/// Главный экран «Заметки»: разделы + заметки без раздела.
class NotesTab extends StatefulWidget {
  const NotesTab({super.key});

  @override
  State<NotesTab> createState() => _NotesTabState();
}

/// Диалог создания раздела — вызывается из HomeShell и NotesTab.
Future<void> showCreateSectionDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  int colorIndex = 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Новый раздел'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Например: Записи к врачам',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Цвет',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AppPalette.noteColors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final selected = i == colorIndex;
                  return GestureDetector(
                    onTap: () => setDialog(() => colorIndex = i),
                    child: Container(
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
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
  if (ok == true && ctrl.text.trim().isNotEmpty) {
    await NotesRepository.instance.createSection(
      title: ctrl.text.trim(),
      colorIndex: colorIndex,
    );
  }
}

class _NotesTabState extends State<NotesTab> {
  final _search = TextEditingController();
  bool _searchOpen = false;
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _enterSelect(String noteId) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      _selected.add(noteId);
    });
  }

  void _toggleSelect(String noteId) {
    setState(() {
      if (_selected.contains(noteId)) {
        _selected.remove(noteId);
        if (_selected.isEmpty) _selectMode = false;
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
  }

  List<Note> _selectedNotes() => NotesRepository.instance.all
      .where((n) => _selected.contains(n.id))
      .toList();

  Future<void> _moveSelected() async {
    final target = await showMoveToSectionPicker(context);
    if (target == null || target == moveCancelled) return;
    for (final n in _selectedNotes()) {
      await NotesRepository.instance.moveToSection(
        n,
        target.isEmpty ? null : target,
      );
    }
    _exitSelect();
    if (mounted) setState(() {});
  }

  Future<void> _archiveSelected() async {
    await archiveNotes(_selectedNotes(), archived: true);
    _exitSelect();
    if (mounted) setState(() {});
  }

  Future<void> _deleteSelected() async {
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
    for (final n in _selectedNotes()) {
      await NotesRepository.instance.delete(n);
    }
    _exitSelect();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _plural(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'заметка';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'заметки';
    return 'заметок';
  }

  Future<void> _sectionMenu(NoteSection section) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                section.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Переименовать / цвет'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppPalette.rose),
              title: const Text(
                'Удалить раздел',
                style: TextStyle(color: AppPalette.rose),
              ),
              subtitle: const Text('Вместе со всеми заметками внутри'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _editSection(section);
    } else if (action == 'delete') {
      await _deleteSection(section);
    }
  }

  Future<void> _editSection(NoteSection section) async {
    final ctrl = TextEditingController(text: section.title);
    int colorIndex = section.colorIndex;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Раздел'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: 'Название'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: AppPalette.noteColors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = i == colorIndex;
                    return GestureDetector(
                      onTap: () => setDialog(() => colorIndex = i),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppPalette.noteColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                size: 18, color: Colors.white)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await NotesRepository.instance.updateSection(
        section.copyWith(title: ctrl.text.trim(), colorIndex: colorIndex),
      );
    }
  }

  Future<void> _deleteSection(NoteSection section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text('Удалить «${section.title}»?'),
        content: Builder(
          builder: (ctx) {
            final count = NotesRepository.instance.noteCount(section.id);
            return Text(
              count == 0
                  ? 'Раздел будет удалён.'
                  : 'ВНИМАНИЕ: вместе с разделом будут безвозвратно '
                      'удалены все его заметки — $count шт. Это действие '
                      'нельзя отменить.',
            );
          },
        ),
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
    if (confirmed == true) {
      await NotesRepository.instance.deleteSection(section);
    }
  }

  void _openSection(NoteSection section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SectionNotesScreen(section: section),
      ),
    );
  }

  Future<void> _openNote(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editNote(Note note) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(existing: note),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<NoteSection>>(
      valueListenable: NotesRepository.instance.sections,
      builder: (context, secs, _) {
        return ValueListenableBuilder<List<Note>>(
          valueListenable: NotesRepository.instance.notes,
          builder: (context, allNotes, _) {
            final q = _search.text.trim().toLowerCase();
            final loose = NotesRepository.instance.notesIn(null);

            if (q.isNotEmpty) {
              final found = NotesRepository.instance.search(q);
              return Column(
                children: [
                  _header('${found.length} ${_plural(found.length)}'),
                  if (_searchOpen) _searchField(),
                  Expanded(child: _searchResults(found)),
                ],
              );
            }

            final total = secs.length + loose.length;
            final subtitle = total == 0
                ? 'Создайте раздел или заметку'
                : [
                    if (secs.isNotEmpty) '${secs.length} ${_pluralSections(secs.length)}',
                    if (loose.isNotEmpty) '${loose.length} ${_plural(loose.length)}',
                  ].join(' · ');

            return Column(
              children: [
                const BetaBanner(compact: true),
                _header(subtitle),
                if (_searchOpen) _searchField(),
                Expanded(
                  child: total == 0
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          physics: const BouncingScrollPhysics(),
                          itemCount: secs.length + loose.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            if (i < secs.length) {
                              final s = secs[i];
                              return StaggeredFadeIn(
                                index: i,
                                child: _SectionCard(
                                  section: s,
                                  count:
                                      NotesRepository.instance.noteCount(s.id),
                                  onTap: () => _openSection(s),
                                  onMenu: () => _sectionMenu(s),
                                ),
                              );
                            }
                            final note = loose[i - secs.length];
                            return StaggeredFadeIn(
                              index: i,
                              child: _LooseNoteCard(
                                note: note,
                                selected: _selected.contains(note.id),
                                selectMode: _selectMode,
                                onTap: () {
                                  if (_selectMode) {
                                    _toggleSelect(note.id);
                                  } else {
                                    _openNote(note);
                                  }
                                },
                                onLongPress: () {
                                  if (_selectMode) {
                                    _toggleSelect(note.id);
                                  } else {
                                    _enterSelect(note.id);
                                  }
                                },
                                onEdit: () => _editNote(note),
                              ),
                            );
                          },
                        ),
                ),
                if (_selectMode)
                  NoteMultiSelectBar(
                    count: _selected.length,
                    onMoveToSection: _moveSelected,
                    onArchive: _archiveSelected,
                    onDelete: _deleteSelected,
                    onClear: _exitSelect,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  String _pluralSections(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'раздел';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'раздела';
    return 'разделов';
  }

  Widget _header(String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MagazineTitle('Планер'),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Архив',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              );
            },
            icon: const Icon(Icons.archive_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) _search.clear();
              });
            },
            icon: Icon(
              _searchOpen ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _search,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Поиск заметок…',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
    );
  }

  Widget _searchResults(List<Note> found) {
    if (found.isEmpty) {
      return const _EmptyState();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      itemCount: found.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final n = found[i];
        final sec = NotesRepository.instance.sectionById(n.sectionId);
        return StaggeredFadeIn(
          index: i,
          child: _SearchNoteCard(
            note: n,
            sectionTitle: sec?.title,
            onTap: () {
              if (sec != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SectionNotesScreen(
                      section: sec,
                      initialNote: n,
                    ),
                  ),
                );
              } else {
                _openNote(n);
              }
            },
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final NoteSection section;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  const _SectionCard({
    required this.section,
    required this.count,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = AppPalette
        .noteColors[section.colorIndex % AppPalette.noteColors.length];
    final textColor = dark ? Colors.white : AppPalette.inkDeep;

    return Material(
      color: dark ? const Color(0xFF1E2F52) : AppPalette.paperCard,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: onMenu,
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.folder_rounded,
                            color: color,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.title.isEmpty
                                    ? 'Без названия'
                                    : section.title,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  height: 1.2,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$count ${_plural(count)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor.withOpacity(0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: onMenu,
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: textColor.withOpacity(0.55),
                          ),
                          tooltip: 'Меню раздела',
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
    );
  }

  String _plural(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'заметка';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'заметки';
    return 'заметок';
  }
}

class _LooseNoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectMode;

  const _LooseNoteCard({
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
      child: selectMode
          ? InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color:
                        selected ? AppPalette.accent : color.withOpacity(0.45),
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
            )
          : Dismissible(
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
                                  label: '${note.voicePaths.length} голос.',
                                  color: AppPalette.violet,
                                  filled: true,
                                ),
                              if (note.hasReminder)
                                NoteChip(
                                  icon: Icons.alarm_on_rounded,
                                  label: formatDateTimeRu(note.reminderDate!),
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
      ),
    );
  }
}

class _SearchNoteCard extends StatelessWidget {
  final Note note;
  final String? sectionTitle;
  final VoidCallback onTap;

  const _SearchNoteCard({
    required this.note,
    this.sectionTitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color =
        AppPalette.noteColors[note.colorIndex % AppPalette.noteColors.length];
    final textColor = dark ? Colors.white : AppPalette.inkDeep;

    return Material(
      color: dark ? const Color(0xFF1E2F52) : AppPalette.paperCard,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Без названия' : note.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (note.hasReminder)
                    const Icon(Icons.alarm_on_rounded,
                        size: 16, color: AppPalette.accent),
                ],
              ),
              if (note.preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withOpacity(0.65),
                  ),
                ),
              ],
              if (sectionTitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  sectionTitle!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppPalette.accent.withOpacity(0.22),
                    AppPalette.sky.withOpacity(0.18),
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.accent.withOpacity(0.2),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: const Icon(
                Icons.edit_note_rounded,
                size: 46,
                color: AppPalette.accent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Пока пусто',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите «Новая» — заметка появится здесь.\nИли «+ раздел» — чтобы группировать заметки.',
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
}
