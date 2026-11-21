import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/nyx/remote_servers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Встроенный сервер МехаВПН: австрийский сервер пользователя.
///
/// Прямой vless://-линк. allowInsecure=1 добавлен, потому что SNI указан
/// как IP-адрес — TLS-сертификат на голый IP почти не выдаётся, без этого
/// параметра проверка сертификата провалится.
///
/// ВНИМАНИЕ: линк содержит UUID (секрет). Не публиковать APK публично.
abstract final class NyxEmbeddedProfile {
  /// Передаётся при сборке: `--dart-define-from-file=secrets.json` (файл не в git, см. secrets.example.json).
  static const String shareLink = String.fromEnvironment('MECHA_SERVER_LINK');
}

/// При первом запуске: если активного профиля нет — создаёт локальный профиль
/// из встроенного vless-линка и делает его активным.
///
/// Почему addLocal, а не addClipboard:
/// `AddProfileNotifier.addClipboard` пропускает ввод через `LinkParser`, а тот
/// распознаёт только http(s)/ftp-ссылки и hiddify://-обёртки. Голый `vless://`
/// он не понимает и уводит в ветку «content» → `addLocal(safeDecodeBase64(..))`
/// — то есть ровно в тот же путь, что и здесь. Разница только в том, что
/// notifier глотает ошибку в свой `AsyncValue` (и показывает свои тосты), а
/// прямой вызов репозитория возвращает `Either<ProfileFailure, String>` —
/// значит в SnackBar можно показать настоящую причину.
///
/// `ProfileRepositoryImpl.addLocal` сам создаёт `ProfileEntity.local(active: true)`,
/// валидирует конфиг через ядро sing-box и вставляет запись в БД; имя профиля
/// берётся из фрагмента линка (`#MyVPN`).
///
/// Проверяем activeProfileProvider (не hasAny): если профили есть, но
/// ни один не активен — всё равно создаём+активируем встроенный.
///
/// Возвращает строку-статус для SnackBar-диагностики:
///  - 'already-has-profile' — активный профиль уже есть
///  - 'created'              — профиль создан и активирован
///  - 'error: ...'           — добавление не удалось
final nyxEnsureEmbeddedProfileProvider = FutureProvider<String>((ref) async {
  final status = await _ensureEmbeddedProfile(ref);

  // Облачный список серверов (если включён) — в фоне: его отсутствие не должно
  // задерживать запуск и подключение ко встроенному серверу.
  unawaited(ref.read(nyxRemoteServersProvider.future).then((_) {}, onError: (Object _) {}));

  return status;
});

Future<String> _ensureEmbeddedProfile(Ref ref) async {
  final active = await ref.read(activeProfileProvider.future);
  if (NyxEmbeddedProfile.shareLink.isEmpty) {
    debugPrint('[NYX] embedded profile: MECHA_SERVER_LINK is not set at build time');
    return 'not-configured';
  }
  if (active != null) {
    debugPrint('[NYX] embedded profile: already active — "${active.name}"');
    return 'already-has-profile';
  }

  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    debugPrint('[NYX] addLocal: start');
    final result = await repo.addLocal(NyxEmbeddedProfile.shareLink).run();
    return result.fold(
      (failure) {
        debugPrint('[NYX] addLocal failed: $failure');
        return 'error: $failure';
      },
      (id) {
        debugPrint('[NYX] addLocal: done, id=$id');
        return 'created';
      },
    );
  } catch (e, st) {
    debugPrint('[NYX] addLocal threw: $e\n$st');
    return 'error: $e';
  }
}
