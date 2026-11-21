import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/nyx/ru_presets_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Скрыт до перезапуска приложения, если пользователь закрыл баннер крестиком.
final ruPresetsBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// МехаВПН: баннер на главном экране. Появляется, когда на телефоне есть приложения
/// из пресета, которые ещё не идут мимо VPN. Тап ведёт на страницу пресета.
class RuPresetsBanner extends ConsumerWidget {
  const RuPresetsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(ruPresetsBannerDismissedProvider)) return const SizedBox.shrink();
    final pending = ref.watch(nyxRuPresetStatusProvider).valueOrNull?.pending.length ?? 0;
    if (pending == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => context.pushNamed('ruPresets'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined, color: colors.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Госуслуги или банк не работают с VPN?',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Нашли $pending приложений — пустим их мимо VPN',
                                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.onSurfaceVariant),
                          tooltip: 'Скрыть',
                          onPressed: () => ref.read(ruPresetsBannerDismissedProvider.notifier).state = true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
