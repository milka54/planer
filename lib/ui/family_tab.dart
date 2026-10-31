import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/family_service.dart';
import '../data/models/family_space.dart';
import 'family_space_screen.dart';
import 'join_space_screen.dart';
import 'widgets.dart';

/// Вкладка «Общие»: семейные / рабочие пространства.
class FamilyTab extends StatefulWidget {
  const FamilyTab({super.key});

  @override
  State<FamilyTab> createState() => _FamilyTabState();
}

class _FamilyTabState extends State<FamilyTab> {
  @override
  void initState() {
    super.initState();
    FamilyService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _createSpace() async {
    final name = await _askName(context, 'Новое пространство', 'Например: Семья');
    if (name == null) return;
    await FamilyService.instance.createSpace(name: name);
    if (mounted) setState(() {});
  }

  /// Вступление по коду-ссылке: planer://join/<token> или просто токен.
  Future<void> _joinByCode() async {
    final name = await showJoinSpaceScreen(context);
    if (name == null) return;
    if (mounted) {
      showSnack(context, 'Вы присоединились к «$name»');
      setState(() {});
    }
  }

  Future<void> _accept(FamilyInvite inv) async {
    await FamilyService.instance.acceptInvite(inv);
    if (mounted) setState(() {});
  }

  Future<void> _decline(FamilyInvite inv) async {
    await FamilyService.instance.declineInvite(inv);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FamilyService.instance.spaces,
        FamilyService.instance.invites,
      ]),
      builder: (context, _) {
        final spaces = FamilyService.instance.spaces.value;
        final invites = FamilyService.instance.invites.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            Row(
              children: [
                const Expanded(child: MagazineTitle('Общие')),
                IconButton.filled(
                  tooltip: 'Новое пространство',
                  onPressed: _createSpace,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Семейные и рабочие заметки с общим доступом',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withOpacity(0.55),
              ),
            ),
            // Заметная карточка-призыв: вступление по приглашению.
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: GlassPanel(
                glow: true,
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppPalette.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.mail_rounded,
                        color: AppPalette.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Есть приглашение?',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Вставьте ссылку и вступите в пространство',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _joinByCode,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.accent,
                        foregroundColor: AppPalette.inkDeep,
                      ),
                      child: const Text('Вступить'),
                    ),
                  ],
                ),
              ),
            ),
            if (invites.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionTitle('ПРИГЛАШЕНИЯ'),
              ...invites.map(
                (inv) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassPanel(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.rose.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.mail_rounded,
                            color: AppPalette.rose,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inv.spaceName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              Text(
                                inv.displayName.isNotEmpty
                                    ? 'Вас зовут: ${inv.displayName} · от ${inv.invitedBy}'
                                    : 'От ${inv.invitedBy}',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Принять',
                          onPressed: () => _accept(inv),
                          icon: const Icon(Icons.check_rounded),
                        ),
                        IconButton(
                          tooltip: 'Отклонить',
                          onPressed: () => _decline(inv),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: SectionTitle('ПРОСТРАНСТВА')),
                TextButton.icon(
                  onPressed: _createSpace,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Создать'),
                ),
              ],
            ),
            if (spaces.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppPalette.accent.withOpacity(0.22),
                              AppPalette.sky.withOpacity(0.16),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          size: 42,
                          color: AppPalette.accent,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Общие заметки',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Создайте пространство и пригласите\n'
                        'близких или коллег',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createSpace,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Новое пространство'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...spaces.asMap().entries.map(
                    (e) => StaggeredFadeIn(
                      index: e.key,
                      child: _SpaceTile(
                        space: e.value,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({required this.space, required this.onChanged});

  final FamilySpace space;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppPalette.accent,
      AppPalette.rose,
      AppPalette.sky,
      AppPalette.mint,
    ];
    final color = colors[space.colorIndex % colors.length];
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: FamilyService.instance.unread,
      builder: (context, unreadMap, _) {
        final unreadCount = unreadMap[space.id] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            glow: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FamilySpaceScreen(space: space),
                  ),
                );
                onChanged();
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.groups_rounded, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          space.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Задачи, список и чат',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppPalette.rose,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<String?> _askName(
  BuildContext context,
  String title,
  String hint,
) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Создать'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return (result == null || result.isEmpty) ? null : result;
}
