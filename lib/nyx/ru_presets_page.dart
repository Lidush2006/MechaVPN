import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/app_based_routing/overview/app_based_routing_notifier.dart';
import 'package:hiddify/nyx/ru_app_presets.dart';
import 'package:hiddify/nyx/ru_presets_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// МехаВПН: отдельная страница с пресетом «Российские сервисы вне VPN».
/// Показывает, какие приложения найдены на телефоне и какие уже идут мимо туннеля,
/// и добавляет недостающие одной кнопкой.
class RuPresetsPage extends ConsumerStatefulWidget {
  const RuPresetsPage({super.key});

  @override
  ConsumerState<RuPresetsPage> createState() => _RuPresetsPageState();
}

class _RuPresetsPageState extends ConsumerState<RuPresetsPage> {
  bool _busy = false;

  Future<void> _apply() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await ref.read(appBasedRoutingProvider.notifier).addRuPreset();
      ref.invalidate(nyxRuPresetStatusProvider);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.added == 0
                  ? 'Все приложения уже идут мимо VPN'
                  : 'Добавлено ${result.added} из ${result.found} — они пойдут мимо VPN',
            ),
          ),
        );
    } catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Не удалось применить: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(nyxRuPresetStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Мимо VPN')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Не удалось проверить приложения: $e')),
        data: (s) {
          final pending = s.pending.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Банки, Госуслуги и маркетплейсы часто не работают через VPN. '
                'Эти приложения пойдут в интернет напрямую, мимо туннеля, '
                'а остальные по-прежнему через VPN.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.apps_rounded, color: theme.colorScheme.onSurfaceVariant),
                title: const Text('Выбрать приложения вручную'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed('appList'),
              ),
              const Divider(),
              const SizedBox(height: 8),
              if (s.installed.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'На телефоне не найдено ни одного приложения из списка.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else ...[
                for (final pkg in s.installed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      s.excluded.contains(pkg) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: s.excluded.contains(pkg) ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    title: Text(NyxRuPresets.nameOf(pkg)),
                    subtitle: Text(s.excluded.contains(pkg) ? 'Идёт напрямую' : 'Пойдёт через VPN'),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || pending == 0 ? null : _apply,
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shield_outlined),
                  label: Text(pending == 0 ? 'Всё уже добавлено' : 'Пустить мимо VPN ($pending)'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
