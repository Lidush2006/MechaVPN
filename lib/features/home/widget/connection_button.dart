import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/nyx/connection_button.dart' as nyx;
import 'package:hiddify/nyx/embedded_profile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// МехаВПН: главная кнопка-шестерёнка на главном экране.
///
/// Заменяет eclipse-кнопку Hiddify на меха-шестерёнку из lib/nyx/,
/// сохраняя всю привязку к VPN-движку через Riverpod:
///   - connectionNotifierProvider — статус туннеля
///   - translationsProvider — тексты статуса
///   - activeProfileProvider / dialogNotifierProvider — онбординг при тапе без профиля
///
/// 9 состояний Hiddify схлопываются в 3 состояния шестерёнки:
///   connected                              → connected  (красная, медленный холостой ход)
///   connecting / waiting / hotReloading /  → starting   (оранжевая, быстрое вращение)
///   disconnecting
///   остальное (disconnected, noProxies,    → off        (серая, без вращения)
///   loading, error)
///
/// NYX: при показе главного экрана один раз запускает
/// [nyxEnsureEmbeddedProfileProvider], который при первом запуске
/// автоматически создаёт профиль из встроенного vless-линка — поэтому тап
/// по шестерёнке сразу подключает, без шторки «добавить профиль».
/// Результат показывается SnackBar'ом (диагностика на этапе отладки).
class ConnectionButton extends ConsumerStatefulWidget {
  const ConnectionButton({super.key});

  @override
  ConsumerState<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends ConsumerState<ConnectionButton> {
  @override
  void initState() {
    super.initState();
    // fireImmediately: провайдер мог отработать ещё до первого build'а.
    ref.listenManual(
      nyxEnsureEmbeddedProfileProvider,
      (previous, next) => _showEmbeddedStatus(next),
      fireImmediately: true,
    );
  }

  /// Диагностический SnackBar о судьбе встроенного профиля.
  void _showEmbeddedStatus(AsyncValue<String> value) {
    final message = switch (value) {
      AsyncData(:final value) => switch (value) {
        'created' => 'Сервер встроен ✓',
        'already-has-profile' => null,
        _ => 'Статус: $value',
      },
      AsyncError(:final error) => 'Исключение: $error',
      _ => null,
    };
    if (message == null) return;
    // initState/сборка кадра: SnackBar можно показать только после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final status = ref.watch(connectionNotifierProvider);

    final gearState = _mapState(status);
    final label = _label(status, t);
    final onTap = _onTap(status, ref);

    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        nyx.ConnectionButton(
          state: gearState,
          onTap: onTap,
          size: 220,
        ),
        const SizedBox(height: 24),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
            color: _labelColor(status, theme),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Цвет подписи по состоянию, как в концепте: красный/оранжевый/бирюзовый/серый.
  Color _labelColor(AsyncValue<ConnectionStatus> status, ThemeData theme) {
    if (status.hasError) return const Color(0xFFFF5A4D);
    return switch (_mapState(status)) {
      nyx.ConnectionState.connected => const Color(0xFF00E5FF),
      nyx.ConnectionState.starting => const Color(0xFFFF6A00),
      nyx.ConnectionState.off => theme.colorScheme.onSurfaceVariant,
    };
  }

  nyx.ConnectionState _mapState(AsyncValue<ConnectionStatus> status) {
    final s = status.valueOrNull;
    if (s is Connected) return nyx.ConnectionState.connected;
    if (s is Connecting || s is Waiting || s is HotReloading || s is Disconnecting) {
      return nyx.ConnectionState.starting;
    }
    return nyx.ConnectionState.off;
  }

  String _label(AsyncValue<ConnectionStatus> status, Translations t) {
    final s = status.valueOrNull;
    return switch (s) {
      Connected() => t.connection.connected,
      Connecting() => t.connection.connecting,
      Waiting() => t.connection.waiting,
      Disconnecting() => t.connection.disconnecting,
      NoAvailableProxies() => t.connection.noAvailableProxies,
      HotReloading() => t.connection.hotReloading,
      Disconnected() => t.connection.tapToConnect,
      _ => t.connection.tapToConnect,
    };
  }

  VoidCallback? _onTap(AsyncValue<ConnectionStatus> status, WidgetRef ref) {
    final s = status.valueOrNull;
    if (s is Connected ||
        s is Connecting ||
        s is Waiting ||
        s is NoAvailableProxies ||
        s is HotReloading) {
      return () => ref.read(connectionNotifierProvider.notifier).toggleConnection();
    }
    // Идёт остановка — второй тап только мешает ядру.
    if (s is Disconnecting) return null;
    // Disconnected, ошибка или ещё не пришёл первый статус (Loading):
    // тап должен работать сразу, поэтому ведём в _connect.
    return () => _connect(ref);
  }

  /// Тап по выключенной кнопке: если активного профиля нет — ведём пользователя
  /// добавить его; иначе показываем предупреждение про экспериментальную фичу
  /// и подключаемся. Поведение перенесено из оригинального Hiddify 1-в-1.
  Future<void> _connect(WidgetRef ref) async {
    // Первый запуск: встроенный профиль может ещё создаваться в фоне.
    // Дожидаемся его, иначе тап сразу после старта открыл бы шторку
    // «добавить профиль» вместо подключения.
    final embedded = await ref.read(nyxEnsureEmbeddedProfileProvider.future);
    if (!mounted) return;

    final embeddedReady = embedded == 'created' || embedded == 'already-has-profile';
    var active = ref.read(activeProfileProvider).valueOrNull;
    if (embeddedReady && active == null) {
      // Поток активного профиля обновляется асинхронно после записи в БД —
      // даём ему до двух секунд, прежде чем считать, что профиля нет.
      for (var i = 0; i < 20 && active == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        active = ref.read(activeProfileProvider).valueOrNull;
      }
    }

    final dialogs = ref.read(dialogNotifierProvider.notifier);
    if (active == null) {
      await dialogs.showNoActiveProfile();
      ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
      return;
    }
    if (await dialogs.showExperimentalFeatureNotice()) {
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    }
  }
}
