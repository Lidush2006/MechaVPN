import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/nyx/ru_app_presets.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/installed_apps.dart';

/// Какие приложения из [NyxRuPresets] стоят на телефоне и какие из них уже идут мимо VPN.
class RuPresetStatus {
  const RuPresetStatus({required this.installed, required this.excluded});

  /// Package names установленных приложений из пресета.
  final List<String> installed;

  /// Среди установленных — уже добавленные в режим «Bypass».
  final Set<String> excluded;

  /// Установленные, но ещё не добавленные.
  List<String> get pending => [
    for (final pkg in installed)
      if (!excluded.contains(pkg)) pkg,
  ];
}

final nyxRuPresetStatusProvider = FutureProvider.autoDispose<RuPresetStatus>((ref) async {
  const empty = RuPresetStatus(installed: [], excluded: {});
  if (!PlatformUtils.isAndroid) return empty;

  final allInstalled = (await InstalledApps.getInstalledApps(
    excludeSystemApps: false,
    excludeNonLaunchableApps: false,
    detectPlatformType: false,
  )).map((e) => e.packageName).toSet();

  final installed = NyxRuPresets.packages.where(allInstalled.contains).toList();
  if (installed.isEmpty) return empty;

  final excluded = await ref
      .read(appProxyDataSourceProvider)
      .watchActivePackages(phonePkgs: installed.toSet(), mode: AppProxyMode.exclude)
      .first;
  return RuPresetStatus(installed: installed, excluded: excluded.toSet());
});
