import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import 'widgets.dart';

/// Экран «Забыли пароль» с понятной инструкцией.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String _sentTo = '';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@') || email.length < 5) {
      showSnack(context, 'Введите корректный email');
      return;
    }
    setState(() => _loading = true);
    final r = await AuthService.instance.resetPassword(email);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r == 'ok') {
        _sent = true;
        _sentTo = email;
      }
    });
    if (r != 'ok') {
      showSnack(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.inkDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Восстановление пароля'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _sent ? _buildSent() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppPalette.accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(
            Icons.lock_reset_rounded,
            size: 42,
            color: AppPalette.accent,
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Забыли пароль?',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Укажите email — мы пришлём письмо со ссылкой для нового пароля.',
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: Colors.white.withOpacity(0.75),
          ),
        ),
        const SizedBox(height: 22),
        GlassPanel(
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'email@example.com',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'Отправить письмо',
          icon: Icons.send_rounded,
          loading: _loading,
          onPressed: _send,
        ),
        const SizedBox(height: 14),
        GlassPanel(
          glow: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppPalette.accentSoft,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'В письме будет ССЫЛКА для смены пароля, а не сам пароль. '
                  'Нажмите на ссылку в письме и придумайте новый пароль (от 6 символов).',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.elasticOut,
          builder: (context, s, child) =>
              Transform.scale(scale: s, child: child),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: AppPalette.mint.withOpacity(0.2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppPalette.mint.withOpacity(0.25),
                  blurRadius: 30,
                ),
              ],
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              size: 52,
              color: AppPalette.mint,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Письмо отправлено!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Мы отправили письмо на\n$_sentTo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 18),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Что делать дальше:',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              _step('1', 'Откройте почту'),
              _step('2', 'Найдите письмо от Firebase / my-notes'),
              _step('3', 'Нажмите ссылку «Follow this link…»'),
              _step('4', 'Придумайте новый пароль (6+ символов)'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'Открыть Gmail',
          icon: Icons.open_in_new_rounded,
          onPressed: () {
            showSnack(context, 'Откройте почтовое приложение на телефоне');
          },
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() => _sent = false),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.35)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Отправить ещё раз / другой email'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Вернуться ко входу',
            style: TextStyle(color: AppPalette.accentSoft),
          ),
        ),
      ],
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.accent.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Text(
              n,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppPalette.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.88),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
