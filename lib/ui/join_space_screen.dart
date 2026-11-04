import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../data/family_service.dart';
import 'widgets.dart';

/// Экран вступления по ссылке-приглашению.
///
/// Поле ввода крупное и подписанное — сразу понятно, что сюда вставлять.
class JoinSpaceScreen extends StatefulWidget {
  const JoinSpaceScreen({super.key, this.initialCode});

  /// Ссылка/код из deep link (planer://join/<token>) — подставляется сразу.
  final String? initialCode;

  @override
  State<JoinSpaceScreen> createState() => _JoinSpaceScreenState();
}

class _JoinSpaceScreenState extends State<JoinSpaceScreen> {
  late final TextEditingController _ctrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialCode ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) showSnack(context, 'Буфер обмена пуст');
      return;
    }
    setState(() => _ctrl.text = text);
    if (mounted) showSnack(context, 'Ссылка вставлена из буфера');
  }

  Future<void> _join() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      showSnack(context, 'Вставьте ссылку или код приглашения');
      return;
    }
    setState(() => _busy = true);
    try {
      final spaceName = await FamilyService.instance.joinByCode(code);
      if (!mounted) return;
      // Успех — возвращаемся назад с результатом.
      Navigator.pop(context, spaceName);
    } catch (e) {
      if (mounted) {
        showSnack(context, '$e');
        setState(() => _busy = false);
      }
    }
  }

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
                    const Expanded(
                      child: Text(
                        'Вступление в пространство',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppPalette.accent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Вас пригласили?',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Вставьте ниже ссылку-приглашение, '
                              'которую вам отправили в мессенджере '
                              '(Telegram, WhatsApp, Viber, SMS — где угодно).',
                              style: TextStyle(fontSize: 15, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Ссылка или код приглашения',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ctrl,
                        maxLines: 3,
                        minLines: 2,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'planer://join/pln…\nили просто код pln…',
                          helperText:
                              'Вставьте всё, что вам прислали — код найдётся автоматически',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 28),
                            child: Icon(Icons.link_rounded),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: AppPalette.accent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('Вставить из буфера обмена'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.35),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _join,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.accent,
                          foregroundColor: AppPalette.inkDeep,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Вступить в пространство',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Как это работает',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '1. Владелец пространства нажимает кнопку «копировать»\n'
                              '2. Отправляет вам ссылку в любом мессенджере\n'
                              '3. Вы вставляете её сюда и нажимаете «Вступить»',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Colors.white70,
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
          ),
        ),
      ),
    );
  }
}

/// Показывает экран вступления и возвращает название пространства (или null).
Future<String?> showJoinSpaceScreen(
  BuildContext context, {
  String? initialCode,
}) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => JoinSpaceScreen(initialCode: initialCode),
    ),
  );
}
