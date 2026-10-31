import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Сведения о доступном обновлении ПК-версии.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.winUrl,
  });

  final String version;
  final String notes;
  final String winUrl;
}

/// Проверка обновлений для Windows-версии.
///
/// Манифест `version.json` лежит в GitHub Releases рядом с установщиком,
/// ссылка вида `releases/latest/download/version.json` всегда указывает
/// на самую свежую версию — её не нужно менять при каждом релизе.
class UpdateService {
  UpdateService._();

  /// Текущая версия приложения. Держать в синхроне с pubspec.yaml.
  static const appVersion = '1.2.0';

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
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final info = UpdateInfo(
        version: '${data['version'] ?? ''}',
        notes: '${data['notes'] ?? ''}',
        winUrl: '${data['win'] ?? ''}',
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

  /// Открывает скачивание новой версии.
  static Future<void> download(UpdateInfo info) async {
    final url = Uri.parse(
      info.winUrl.isNotEmpty
          ? info.winUrl
          : manifestUrl.replaceFirst('version.json', 'planer-win64.zip'),
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
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
