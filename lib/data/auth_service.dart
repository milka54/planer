import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import 'cloud_service.dart';
import 'firebase_rest.dart';
import 'models/note.dart';
import 'storage.dart';

/// Гостевой / облачный режим + Firebase Auth.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  bool cloudReady = false;

  final ValueNotifier<String?> userKey = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isGuest = ValueNotifier<bool>(true);
  final ValueNotifier<String?> userEmail = ValueNotifier<String?>(null);

  String get ownerKey => userKey.value ?? 'guest';

  Future<void> init() async {
    try {
      fb.FirebaseAuth.instance.setLanguageCode('ru');
    } catch (_) {}
    final mode = StorageService.instance.mode;
    final stored = StorageService.instance.ownerKey;

    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user != null) {
        cloudReady = true;
        userKey.value = user.uid;
        isGuest.value = false;
        userEmail.value = user.email;
        if (stored != user.uid) {
          await StorageService.instance.setOwnerKey(user.uid);
          await StorageService.instance.setMode('cloud');
        }
        return;
      }
    } catch (e) {
      debugPrint('Firebase session: $e');
    }

    if (mode == 'cloud' && stored != 'guest') {
      // Пробуем восстановить REST-сессию (Windows/desktop).
      await _restoreRestSession(stored);
      userKey.value = stored;
      isGuest.value = false;
    } else {
      userKey.value = 'guest';
      isGuest.value = true;
      await StorageService.instance.setOwnerKey('guest');
      await StorageService.instance.setMode('guest');
    }
  }

  Future<void> _saveRestSession() async {
    await StorageService.instance.setRestSession({
      'refreshToken': FirebaseRest.instance.refreshToken,
      'uid': FirebaseRest.instance.uid,
      'email': FirebaseRest.instance.email,
    });
  }

  Future<void> _restoreRestSession(String storedUid) async {
    final s = StorageService.instance.restSession;
    if (s == null) return;
    try {
      FirebaseRest.instance.refreshToken = s['refreshToken'] as String?;
      FirebaseRest.instance.uid = s['uid'] as String?;
      FirebaseRest.instance.email = s['email'] as String?;
      userEmail.value = FirebaseRest.instance.email;
      if (FirebaseRest.instance.refreshToken != null) {
        // Пробуем обновить токен — заодно проверяем, что сессия жива.
        await FirebaseRest.instance.refreshSession();
      }
    } catch (e) {
      debugPrint('restore rest session: $e');
    }
  }

  Future<void> _clearRestSession() async {
    await FirebaseRest.instance.signOut();
    await StorageService.instance.setRestSession(null);
  }

  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await _enterCloud(uid, cred.user?.email, migrate: true);
      return 'ok';
    } on fb.FirebaseAuthException catch (e) {
      return _mapAuthError(e);
    } catch (_) {
      // Нет Firebase SDK (Windows/desktop) — вход через REST.
      return _signInRest(email, password);
    }
  }

  Future<String> _signInRest(String email, String password) async {
    try {
      final data = await FirebaseRest.instance.signIn(
        email.trim(),
        password,
      );
      await _saveRestSession();
      await _enterCloud(
        data['localId'] as String,
        data['email'] as String? ?? email.trim(),
        migrate: true,
      );
      return 'ok';
    } on RestAuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Не удалось войти. Проверьте соединение.';
    }
  }

  Future<String> register({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await fb.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await _enterCloud(uid, cred.user?.email, migrate: true);
      return 'ok';
    } on fb.FirebaseAuthException catch (e) {
      return _mapAuthError(e);
    } catch (_) {
      return _registerRest(email, password);
    }
  }

  Future<String> _registerRest(String email, String password) async {
    try {
      final data = await FirebaseRest.instance.register(
        email.trim(),
        password,
      );
      await _saveRestSession();
      await _enterCloud(
        data['localId'] as String,
        data['email'] as String? ?? email.trim(),
        migrate: true,
      );
      return 'ok';
    } on RestAuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Не удалось зарегистрироваться. Проверьте соединение.';
    }
  }

  Future<String> resetPassword(String email) async {
    try {
      await fb.FirebaseAuth.instance.setLanguageCode('ru');
      await fb.FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.trim());
      return 'ok';
    } on fb.FirebaseAuthException catch (e) {
      return _mapAuthError(e);
    } catch (_) {
      try {
        await FirebaseRest.instance.sendPasswordReset(email.trim());
        return 'ok';
      } on RestAuthException catch (e) {
        return e.message;
      } catch (_) {
        return 'Не удалось отправить письмо. Проверьте интернет.';
      }
    }
  }

  /// Смена пароля текущего пользователя (нужен текущий пароль).
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = fb.FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        return 'Сначала войдите в аккаунт';
      }
      if (newPassword.length < 6) {
        return 'Новый пароль — минимум 6 символов';
      }
      if (newPassword != currentPassword && newPassword.length < 6) {
        return 'Слишком простой пароль';
      }

      final cred = fb.EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
      return 'ok';
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'Текущий пароль указан неверно';
      }
      return _mapAuthError(e);
    } catch (_) {
      return 'Не удалось изменить пароль';
    }
  }

  String? validatePassword(String password) {
    if (password.isEmpty) return 'Введите пароль';
    if (password.length < 6) {
      return 'Пароль должен быть не короче 6 символов';
    }
    return null;
  }

  Future<void> _enterCloud(String uid, String? email,
      {required bool migrate}) async {
    List<Note> migratedNotes = const [];
    if (migrate) {
      migratedNotes = await StorageService.instance.migrateGuestNotesTo(uid);
    }
    await StorageService.instance.setOwnerKey(uid);
    await StorageService.instance.setMode('cloud');
    userKey.value = uid;
    isGuest.value = false;
    userEmail.value = email;
    cloudReady = true;

    // Полная выгрузка в облако: и заметки, и разделы. Раньше разделы
    // отправлялись только вместе с перенесёнными заметками, из-за чего
    // «пустые» разделы и разделы без миграции терялись на новых устройствах.
    try {
      final notesToPush = migratedNotes.isNotEmpty
          ? migratedNotes
          : await StorageService.instance.loadNotes(uid);
      final secs = await StorageService.instance.loadSections(uid);
      if (notesToPush.isNotEmpty) {
        await CloudNotesService.instance.pushAll(uid, notesToPush);
      }
      if (secs.isNotEmpty) {
        await CloudNotesService.instance.pushAllSections(uid, secs);
      }
    } catch (e) {
      debugPrint('migrate push: $e');
    }
  }

  Future<void> continueAsGuest() async {
    await StorageService.instance.setOwnerKey('guest');
    await StorageService.instance.setMode('guest');
    userKey.value = 'guest';
    isGuest.value = true;
    userEmail.value = null;
  }

  Future<void> signOut() async {
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (_) {}
    await _clearRestSession();
    final previous = userKey.value;
    if (previous != null && previous != 'guest') {
      // Заметки остаются на устройстве: копируем в гостевое хранилище.
      await StorageService.instance.copyOwnerNotesToGuest(previous);
    }
    await StorageService.instance.setOwnerKey('guest');
    await StorageService.instance.setMode('guest');
    userKey.value = 'guest';
    isGuest.value = true;
    userEmail.value = null;
  }

  String _mapAuthError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Пользователь не найден';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Неверный email или пароль';
      case 'email-already-in-use':
        return 'Этот email уже зарегистрирован';
      case 'invalid-email':
        return 'Некорректный email';
      case 'weak-password':
        return 'Слишком простой пароль (мин. 6 символов)';
      case 'network-request-failed':
        return 'Нет соединения с интернетом';
      case 'too-many-requests':
        return 'Слишком много попыток. Попробуйте позже';
      default:
        return e.message ?? 'Ошибка авторизации';
    }
  }
}
