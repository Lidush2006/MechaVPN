import 'package:flutter/material.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// МехаВПН: список серверов на главном экране. Активный отмечен красным,
/// тап по строке делает сервер активным (если VPN запущен, он переподключится).
class NyxServerList extends ConsumerWidget {
  const NyxServerList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    if (profiles.isEmpty) return const SizedBox.shrink();

    final activeId = ref.watch(activeProfileProvider).valueOrNull?.id;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(
              'СЕРВЕРЫ',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < profiles.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: colors.outlineVariant),
                  _ServerRow(
                    name: profiles[i].name,
                    selected: profiles[i].id == activeId,
                    onTap: () => _select(ref, profiles[i].id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _select(WidgetRef ref, String id) async {
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.setAsActive(id).run();
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: selected ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? colors.primary : colors.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name.isEmpty ? 'MyVPN' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ),
            if (selected)
              Text(
                'АКТИВЕН',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.5,
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
