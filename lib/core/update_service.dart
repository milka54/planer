import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Сведения о доступном обновлении ПК-версии.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.winUrl,
    required this.winZipUrl,
  });

  final String version;
  final String notes;

  /// Установщик (legacy, для первой установки).
  final String winUrl;

  /// Портативный zip-пакет для обновления из приложения без установщика.
  final String winZipUrl;
}

/// Проверка обновлений для Windows-версии.
///
/// Манифест `version.json` лежит в GitHub Releases рядом с установщиком,
/// ссылка вида `releases/latest/download/version.json` всегда указывает
/// на самую свежую версию — её не нужно менять при каждом релизе.
class UpdateService {
  UpdateService._();

  /// Текущая версия приложения. Держать в синхроне с pubspec.yaml.
  static const appVersion = '1.3.6';

  /// URL манифеста обновлений (GitHub Releases, всегда последняя версия).
  static const manifestUrl =
      'https://github.com/milka54/planer/releases/latest/download/version.json';

  static UpdateInfo? _cached;
  static bool _checking = false;

  /// Проверяет наличие обновления. Возвращает UpdateInfo, если версия новее.
  static Future<UpdateInfo?> check() async {
    if (_checking) return _cached;
    _checking = true;
    try {
      final resp = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo(
        version: '${data['version'] ?? ''}',
        notes: '${data['notes'] ?? ''}',
        winUrl: '${data['win'] ?? ''}',
        winZipUrl: '${data['winZip'] ?? ''}',
      );
      if (isNewer(info.version, appVersion)) {
        _cached = info;
        return info;
      }
      _cached = null;
      return null;
    } catch (e) {
      debugPrint('update check: $e');
      return null;
    } finally {
      _checking = false;
    }
  }

  /// Ставит обновление прямо из приложения: скачивает zip-пакет, заменяет
  /// файлы программы на месте и перезапускает её — без установщика и без
  /// повторной установки. Если в манифесте есть только установщик (legacy),
  /// используется прежний тихий запуск Inno.
  static Future<void> download(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (info.winZipUrl.isEmpty) {
      await _downloadWithInstaller(info, onProgress: onProgress);
      return;
    }

    final temp = Directory.systemTemp;
    final zipPath = '${temp.path}\\planer_update.zip';
    final pkgDir = Directory('${temp.path}\\planer_update_pkg');

    await _fetchFile(info.winZipUrl, zipPath, onProgress: onProgress);

    if (pkgDir.existsSync()) pkgDir.deleteSync(recursive: true);
    pkgDir.createSync(recursive: true);
    final extract =
        await Process.run('tar', ['-xf', zipPath, '-C', pkgDir.path]);
    if (extract.exitCode != 0) {
      throw Exception('extract failed: ${extract.stderr}');
    }

    final appDir = File(Platform.resolvedExecutable).parent.path;
    // Скрипт замены: ждёт выхода приложения, копирует файлы поверх каталога
    // программы (с повышением прав, если каталог защищён) и запускает её снова.
    final copyScript =
        "Copy-Item -Path '${pkgDir.path}\\*' -Destination '$appDir' -Recurse -Force";
    final restart = 'Start-Process -FilePath \'$appDir\\planer.exe\'';
    final script = '\$admin = ([Security.Principal.WindowsPrincipal]'
        '[Security.Principal.WindowsIdentity]::GetCurrent())'
        '.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)\n'
        'Start-Sleep -Seconds 5\n'
        'if (\$admin) {\n'
        '  $copyScript\n'
        '} else {\n'
        '  try {\n'
        "    Start-Process -FilePath 'powershell' -Verb RunAs -Wait "
        "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass',"
        "'-EncodedCommand','${_psEncode(copyScript)}'\n"
        '  } catch {\n'
        '    \$global:updFailed = \$true\n'
        '  }\n'
        '}\n'
        'if (-not \$global:updFailed) {\n'
        '  Start-Sleep -Seconds 2\n'
        '  \$check = Get-Item \'$appDir\\planer.exe\' -ErrorAction SilentlyContinue\n'
        '  if (\$check -and \$check.LastWriteTime -gt (Get-Date).AddMinutes(-5)) {\n'
        '    $restart\n'
        '  } else {\n'
        '    \$global:updFailed = \$true\n'
        '  }\n'
        '}\n'
        'if (\$global:updFailed) {\n'
        '  Add-Type -AssemblyName System.Windows.Forms\n'
        '  [System.Windows.Forms.MessageBox]::Show('
        "'Не удалось обновить автоматически. Установите вручную: "
        "https://github.com/milka54/planer/releases/latest','Планер')\n"
        '  $restart\n'
        '}\n';

    await Process.start(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', _psEncode(script)],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  /// Прежний путь: тихая установка Inno + автоперезапуск.
  static Future<void> _downloadWithInstaller(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final url = Uri.parse(
      info.winUrl.isNotEmpty
          ? info.winUrl
          : manifestUrl.replaceFirst('version.json', 'planer-setup.exe'),
    );
    final tmp = File('${Directory.systemTemp.path}\\planer-setup-update.exe');
    await _fetchFile(url.toString(), tmp.path, onProgress: onProgress);

    // Тихая установка + автоперезапуск: bat ждёт завершения текущего
    // процесса, запускает setup и открывает обновлённое приложение.
    final bat = File('${Directory.systemTemp.path}\\planer_update_run.bat');
    await bat.writeAsString(
      '@echo off\r\n'
      'ping -n 6 127.0.0.1 >nul\r\n'
      'start "" /wait "${tmp.path}" /SILENT /SP- /CLOSEAPPLICATIONS\r\n'
      'start "" "${Platform.resolvedExecutable}"\r\n',
      flush: true,
    );
    await Process.start(
      bat.path,
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  static Future<void> _fetchFile(
    String url,
    String path, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers['User-Agent'] = 'PlanerUpdater';
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? 0;
      var received = 0;
      final sink = File(path).openWrite();
      await sink.addStream(resp.stream.map((chunk) {
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
        return chunk;
      }));
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// PowerShell `-EncodedCommand` ожидает base64 от UTF-16LE.
  static String _psEncode(String script) {
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.add(unit & 0xff);
      bytes.add((unit >> 8) & 0xff);
    }
    return base64.encode(bytes);
  }

  /// true, если [a] новее [b] (сравнение "1.2.0" по частям).
  static bool isNewer(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va > vb) return true;
      if (va < vb) return false;
    }
    return false;
  }

  /// Проверка обновлений имеет смысл только на Windows-версии.
  static bool get supportedOnThisPlatform => !kIsWeb && Platform.isWindows;
}
