# ПЛАНЕР — ПОЛНАЯ ШПАРГАЛКА ПРОЕКТА
## (для возврата к работе после долгого перерыва)

**Обновлено:** 19.10.2026  
**Пользователь файлы не переносит и не удаляет.**

---

## 1. Что за проект и зачем

Android-приложение **«Планер»** (Flutter) — заметки с напоминаниями и голосовыми.

**Цели:**
- Уникальный красивый UI (не шаблонный)
- Local-first: работает офлайн, потом облако
- Гостевой режим + Firebase (регистрация)
- Freemium: сейчас beta/бесплатно, регистрация станет платной
- Публикация в **RuStore** (не Google Play)

**Как работаем:** пользователь ставит задачу → я правлю → он тестирует на телефоне (TECNO BG6) → правки → релиз. Debug/APK ставим на устройство. Release для RuStore — только по просьбе.

---

## 2. Где что лежит

```
D:\Projects\Planer\                 # ИСХОДНИКИ Flutter (после восстановления)
  PROJECT-HANDBOOK.md               # ЭТОТ ФАЙЛ
  RUSTORE-ОБНОВЛЕНИЕ-1.1.0.txt      # готовая инфа для консоли RuStore
  lib\ android\ assets\
  rustore-release\
    01-publish\                     # APK, pepk_out.zip, uploadcert.pem
    02-store\                       # тексты, иконка, скриншоты
    03-signing\                     # КЛЮЧИ (секретно!)
    04-docs\                        # политика, чек-лист
    05-archive\                     # APK 1.0.0

D:\dev\                             # SDK/инструменты (read-only)
  android-sdk\ Android Studio\ Git\ gradle-home\
  planer\                           # старый архив (не писать)
  rustore-release\                  # старый архив материалов RuStore
```

---

## 3. Технические данные

| Параметр | Значение |
|---|---|
| Package ID | `ru.planer.notes` |
| MainActivity package | `com.example.my_notes` (НЕ менять!) |
| Версия | **1.1.0** (versionCode 2) |
| Flutter / Dart | 3.47.6 / 3.13.5 |
| Firebase | project `my-notes-71034` |
| Keystore | `android/upload-keystore.jks`, alias `upload`, pass `planer2026` |
| SHA-256 | `8c7938389860de02475ccf1331010aae56e5749ae169cba0a60dff40d8ddee71` |

**Пакеты для голоса:** `record` 7, `audioplayers` 6.

---

## 4. Архитектура (кратко)

**Модели:**
- `NoteSection` — раздел (название, цвет)
- `Note` — заголовок, текст, напоминание, `sectionId`, `voicePaths`
- Чек-листов (NoteItem) больше НЕТ

**Данные:** SharedPreferences JSON → Firestore `users/{uid}/notes|sections`

**Правила:**
- Гость при входе: заметки СЛИВАЮТСЯ с аккаунтом
- Выход: заметки ОСТАЮТСЯ на устройстве
- Голос: только локально (не в облако)
- Фон из галереи: копируется в постоянное хранилище

**Код:**
```
lib/main.dart
lib/core/theme.dart
lib/data/models/note.dart
lib/data/{storage,auth_service,cloud_service,notes_repository,voice_service,notifications,reminder_service}.dart
lib/ui/{home_shell,notes_tab,section_notes_screen,note_editor,note_detail,settings_tab,reminders_tab,calendar_screen,widgets,auth_hub,onboarding}.dart
```

**UI:**
- Вкладки: Заметки | Напоминания | Настройки
- FAB: слева «Раздел», справа «Новая»
- Заметки без раздела — на главном экране
- «⋮» на заметке → «Перенести в раздел»

---

## 5. Как собрать

```powershell
$env:ANDROID_HOME="D:\dev\android-sdk"
$env:ANDROID_SDK_ROOT="D:\dev\android-sdk"
$env:GRADLE_USER_HOME="D:\dev\gradle-home"
$env:JAVA_HOME="D:\dev\Android Studio\jbr"
$env:PUB_HOSTED_URL="https://pub.dev"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"
$env:PATH="C:\flutter\flutter\bin;D:\dev\Git\cmd;D:\dev\Android Studio\jbr\bin;$env:PATH"

cd D:\Projects\Planer
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

**Важно:** Java только JBR из Android Studio. Системная Java 8 — нельзя.  
ADB TECNO часто offline → `adb kill-server` + переподключить.

---

## 6. RuStore — что и как

**Статус:** подпись ПРИНЯТА. Ждём публикацию 1.0.0, потом заливаем 1.1.0.

**Для обновления** — открой `D:\dev\RUSTORE-ОБНОВЛЕНИЕ-1.1.0.txt`:
там changelog, описание, версия, пути к файлам.

**PEPK (если подпись заново):**
- Java JBR (не Java 8!)
- keystore `planer.jks` (JKS)
- alias `upload`, pass `planer2026`, **раскладка EN**
- encryptionkey из консоли RuStore
- на выходе: `pepk_out.zip` + `uploadcert.pem`

---

## 7. Что уже сделано (v1.1.0)

- [x] Разделы заметок (создание, цвет, удаление)
- [x] Голосовые вложения
- [x] Перенос заметки в раздел
- [x] Заметки без раздела на главном
- [x] Кнопка «Раздел» слева (как «Новая»)
- [x] Фон галереи не пропадает
- [x] Настройки читаемы на любых фонах
- [x] Гость↔облако без потери заметок
- [x] Новая иконка
- [x] Release APK 1.1.0 + подпись RuStore

---

## 8. Что осталось

- [ ] Опубликовать 1.0.0 в RuStore
- [ ] Залить 1.1.0 (по шпаргалке)
- [ ] Обновить скриншоты под новые функции
- [ ] Указать email поддержки
- [ ] (если скажет) голос в облако
- [ ] Firebase email templates или свой сервер

---

## 9. Правила

1. Всё по-русски
2. Не собирать release без просьбы
3. Не менять дизайн молча
4. Не трогать SDK, legacy, keystore-пароли
5. Тест — на реальном телефоне
