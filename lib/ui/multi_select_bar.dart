import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';

/// Активен режим множественного выбора заметок (NotesTab / SectionNotesScreen).
/// HomeShell слушает его, чтобы прятать FAB под панелью выбора.
final ValueNotifier<bool> notesSelectActive = ValueNotifier<bool>(false);

/// Нижняя панель действий при множественном выборе заметок.
class NoteMultiSelectBar extends StatelessWidget {
  const NoteMultiSelectBar({
    super.key,
    required this.count,
    required this.onMoveToSection,
    required this.onArchive,
    required this.onDelete,
    required this.onClear,
    this.bottomGap = 12,
  });

  final int count;
  final VoidCallback onMoveToSection;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  /// Отступ снизу (панель должна быть выше NavigationBar на главном экране).
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, bottomGap),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2F52),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Снять выбор',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
            Expanded(
              child: Text(
                'Выбрано: $count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'В раздел',
              onPressed: count == 0 ? null : onMoveToSection,
              icon: Icon(Icons.drive_file_move_rounded,
                  color: AppPalette.accent),
            ),
            IconButton(
              tooltip: 'В архив',
              onPressed: count == 0 ? null : onArchive,
              icon: const Icon(Icons.archive_rounded, color: AppPalette.sky),
            ),
            IconButton(
              tooltip: 'Удалить',
              onPressed: count == 0 ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppPalette.rose),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор раздела для переноса. Возвращает id раздела или null («Без раздела»).
/// Специальное значение `_cancel` — пользователь закрыл без действия.
const String moveCancelled = '__cancel__';

Future<String?> showMoveToSectionPicker(BuildContext context) async {
  final secs = NotesRepository.instance.allSections;
  return showModalBottomSheet<String>(
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
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Без раздела'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final s in secs)
            ListTile(
              leading: Icon(
                Icons.folder_rounded,
                color: AppPalette
                    .noteColors[s.colorIndex % AppPalette.noteColors.length],
              ),
              title: Text(s.title),
              onTap: () => Navigator.pop(ctx, s.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Помечает заметки архивными/нет одной операцией.
Future<void> archiveNotes(List<Note> notes, {required bool archived}) async {
  for (final n in notes) {
    if (n.archived != archived) {
      final updated = n.copyWith(archived: archived);
      await NotesRepository.instance.replaceInMemory(updated);
    }
  }
}
