import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/nyx/ru_presets_banner.dart';
import 'package:hiddify/nyx/server_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

/// NYX: главный экран МехаВПН — только шестерёнка, статус подключения и
/// активный сервер. Карта мира и баннер «Быстрые настройки» убраны: профиль
/// встроен, лишние двери в настройки не нужны.
class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Assets.images.logo.svg(
              width: 26,
              height: 26,
              colorFilter: const ColorFilter.mode(Color(0xFFE10600), BlendMode.srcIn),
            ),
            const Gap(10),
            Text(
              "MECHA VPN",
              style: TextStyle(
                fontFamily: 'Exo2',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 4,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 600,
              ),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                child: CustomScrollView(
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    MultiSliver(
                      children: [
                        const SliverToBoxAdapter(child: NyxServerList()),
                        const SliverToBoxAdapter(child: RuPresetsBanner()),
                        // NYX: const убран намеренно — внутри ConnectionButton()
                        // и ActiveProxyDelayIndicator() несовместимы с const-контекстом.
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ConnectionButton(),
                              ActiveProxyDelayIndicator(),
                              Gap(32),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
