import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/note.dart';
import '../data/notes_repository.dart';
import 'note_detail.dart';
import 'widgets.dart';

/// Экран «Архив»: заметки, убранные в архив.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: ThemedBackground(
        assetPath: ThemeOption.night.backgroundAsset,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Expanded(child: MagazineTitle('Архив')),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Заметки в архиве скрыты из основного списка',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<Note>>(
                  valueListenable: NotesRepository.instance.notes,
                  builder: (context, _, __) {
                    final archived = NotesRepository.instance.archivedSorted;
                    if (archived.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.archive_rounded,
                              size: 56,
                              color: Colors.white.withOpacity(0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Архив пуст',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: archived.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final note = archived[i];
                        return _ArchivedTile(
                          note: note,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NoteDetailScreen(note: note),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                          onRestore: () async {
                            await NotesRepository.instance
                                .toggleArchive(note);
                            if (mounted) setState(() {});
                          },
                          onDelete: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                title: const Text('Удалить заметку?'),
                                content: Text(note.title),
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
                              if (mounted) setState(() {});
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchivedTile extends StatelessWidget {
  const _ArchivedTile({
    required this.note,
    required this.onTap,
    required this.onRestore,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.sky.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.archive_rounded,
                  color: AppPalette.sky),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title.isEmpty ? 'Без заголовка' : note.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note.preview.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note.preview,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Вернуть',
              onPressed: onRestore,
              icon: const Icon(Icons.unarchive_rounded),
            ),
            IconButton(
              tooltip: 'Удалить',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
