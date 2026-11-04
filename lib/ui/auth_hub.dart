import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/notes_repository.dart';
import 'forgot_password_screen.dart';
import 'home_shell.dart';
import 'widgets.dart';

class AuthHubScreen extends StatefulWidget {
  const AuthHubScreen({super.key});

  @override
  State<AuthHubScreen> createState() => _AuthHubScreenState();
}

class _AuthHubScreenState extends State<AuthHubScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      showSnack(context, 'Введите корректный email');
      return;
    }
    if (pass.length < 6) {
      showSnack(context, 'Пароль — минимум 6 символов');
      return;
    }
    setState(() => _loading = true);
    final result = _registerMode
        ? await AuthService.instance
            .register(email: email, password: pass)
        : await AuthService.instance.signIn(email: email, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result == 'ok') {
      // Подтягиваем заметки нового аккаунта до перехода
      await NotesRepository.instance.load();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } else {
      showSnack(context, result);
    }
  }

  Future<void> _guest() async {
    await AuthService.instance.continueAsGuest();
    await NotesRepository.instance.load();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  Future<void> _forgot() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ThemedBackground(
        assetPath: ThemeOption.night.backgroundAsset,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _registerMode ? 'Создать аккаунт' : 'С возвращением',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _registerMode
                          ? 'Синхронизируйте заметки между устройствами'
                          : 'Войдите, чтобы открыть облачный режим',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.72)),
                    ),
                    const SizedBox(height: 16),
                    const BetaBanner(),
                    const SizedBox(height: 8),
                    GlassPanel(
                      child: Column(
                        children: [
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Пароль',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(
                            label: _registerMode
                                ? 'Зарегистрироваться'
                                : 'Войти',
                            loading: _loading,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(
                                () => _registerMode = !_registerMode),
                            child: Text(
                              _registerMode
                                  ? 'Уже есть аккаунт? Войти'
                                  : 'Нет аккаунта? Регистрация',
                              style: TextStyle(color: AppPalette.accentSoft),
                            ),
                          ),
                          if (!_registerMode)
                            TextButton(
                              onPressed: _forgot,
                              child: Text(
                                'Забыли пароль?',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _guest,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.35)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.person_outline_rounded),
                      label: const Text('Продолжить как гость'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
