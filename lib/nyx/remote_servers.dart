import 'dart:async';

import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// МехаВПН: дополнительные серверы, которые приложение подтягивает из сети,
/// чтобы не пересобирать APK ради нового узла.
///
/// Формат файла по [url] — либо просто массив ссылок:
///
/// ```json
/// ["vless://...", "vless://..."]
/// ```
///
/// либо объект с полем `servers`:
///
/// ```json
/// { "servers": ["vless://...", "vless://..."] }
/// ```
///
/// Правила:
///  - добавляются только ссылки поддерживаемых протоколов;
///  - каждый линк добавляется один раз (список уже добавленных хранится в
///    SharedPreferences, поэтому повторный запуск не плодит дубликаты);
///  - новые профили создаются **неактивными**: активным остаётся встроенный
///    сервер, пользователь сам выбирает другой в списке профилей.
///
/// ВАЖНО: линки содержат UUID. Если файл лежит в публичном репозитории —
/// сервер фактически открыт всем, кто этот репозиторий найдёт. Держи его на
/// своём домене или в приватном месте.
abstract final class NyxRemoteServers {
  /// Пустая строка — облачный список выключен, приложение работает только
  /// со встроенным сервером.
  ///
  /// Пример: 'https://raw.githubusercontent.com/<user>/<repo>/main/servers.json'
  static const url = '';

  static const _addedKey = 'nyx.remote.servers.added';

  static bool get enabled => url.isNotEmpty;

  static bool _supported(String link) =>
      link.startsWith('vless://') ||
      link.startsWith('vmess://') ||
      link.startsWith('trojan://') ||
      link.startsWith('ss://') ||
      link.startsWith('hysteria2://') ||
      link.startsWith('hy2://');
}

/// Скачивает список и добавляет те серверы, которых у приложения ещё не было.
/// Возвращает число добавленных профилей. Ошибки сети не пробрасываются:
/// отсутствие облачного списка не должно мешать подключению ко встроенному.
final nyxRemoteServersProvider = FutureProvider<int>((ref) async {
  if (!NyxRemoteServers.enabled) return 0;

  final response = await ref
      .read(httpClientProvider)
      .get<dynamic>(NyxRemoteServers.url)
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200 || response.data == null) return 0;

  final data = response.data;
  final raw = <dynamic>[
    if (data is List) ...data,
    if (data is Map && data['servers'] is List) ...(data['servers'] as List),
  ];
  final links = raw.whereType<String>().where(NyxRemoteServers._supported).toList();
  if (links.isEmpty) return 0;

  final prefs = await ref.read(sharedPreferencesProvider.future);
  final seen = (prefs.getStringList(NyxRemoteServers._addedKey) ?? const <String>[]).toSet();
  final fresh = links.where((link) => !seen.contains(link)).toList();
  if (fresh.isEmpty) return 0;

  final repo = await ref.read(profileRepositoryProvider.future);
  var added = 0;
  for (final link in fresh) {
    final result = await repo.addLocal(link, active: false).run();
    if (result.isRight()) {
      added++;
      seen.add(link);
    }
  }
  if (added > 0) await prefs.setStringList(NyxRemoteServers._addedKey, seen.toList());
  return added;
});
