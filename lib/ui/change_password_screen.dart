import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import 'widgets.dart';

/// Смена пароля текущего пользователя.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure3 = true;

  double get _strength {
    final p = _new.text;
    if (p.isEmpty) return 0;
    var s = 0.25;
    if (p.length >= 8) s += 0.25;
    if (p.contains(RegExp(r'[A-Z]'))) s += 0.2;
    if (p.contains(RegExp(r'[0-9]'))) s += 0.15;
    if (p.contains(RegExp(r'[^A-Za-z0-9]'))) s += 0.15;
    return s.clamp(0, 1);
  }

  Color get _strengthColor {
    if (_strength < 0.4) return AppPalette.rose;
    if (_strength < 0.7) return AppPalette.accent;
    return AppPalette.mint;
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cur = _current.text;
    final next = _new.text;
    final conf = _confirm.text;

    final err = AuthService.instance.validatePassword(next);
    if (err != null) {
      showSnack(context, err);
      return;
    }
    if (next != conf) {
      showSnack(context, 'Пароли не совпадают');
      return;
    }
    if (cur == next) {
      showSnack(context, 'Новый пароль совпадает со старым');
      return;
    }

    setState(() => _loading = true);
    final r = await AuthService.instance.changePassword(
      currentPassword: cur,
      newPassword: next,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (r == 'ok') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Пароль изменён'),
          content: const Text('Используйте новый пароль при следующем входе.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Хорошо'),
            ),
          ],
        ),
      );
    } else {
      showSnack(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Изменить пароль')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassPanel(
            child: Column(
              children: [
                TextField(
                  controller: _current,
                  obscureText: _obscure1,
                  decoration: InputDecoration(
                    hintText: 'Текущий пароль',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure1
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _new,
                  obscureText: _obscure2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Новый пароль (от 6 символов)',
                    prefixIcon: const Icon(Icons.lock_reset_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure2
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_new.text.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _strength,
                      minHeight: 6,
                      backgroundColor: Colors.black12,
                      valueColor:
                          AlwaysStoppedAnimation(_strengthColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _strength < 0.4
                          ? 'Слабый пароль'
                          : _strength < 0.7
                              ? 'Нормальный пароль'
                              : 'Надёжный пароль',
                      style: TextStyle(
                        fontSize: 12,
                        color: _strengthColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _confirm,
                  obscureText: _obscure3,
                  decoration: InputDecoration(
                    hintText: 'Повторите новый пароль',
                    prefixIcon: const Icon(Icons.done_all_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure3
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure3 = !_obscure3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Сменить пароль',
            icon: Icons.check_rounded,
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 12),
          Text(
            'Для смены пароля нужно подтвердить текущий. '
            'Если вы его забыли — выйдите и используйте «Забыли пароль?».',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}
