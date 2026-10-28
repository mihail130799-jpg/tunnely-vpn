import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/xray_config.dart';
import '../models/subscription.dart';
import '../providers/app_controller.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'logs_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appControllerProvider);
    final ctrl = ref.read(appControllerProvider.notifier);
    final st = s.settings;
    final tc = context.tc;

    return Scaffold(
      backgroundColor: tc.bgGradient.last,
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Section('Подключение', [
            SwitchListTile(
              title: const Text('Подключаться при запуске'),
              subtitle: const Text('Сразу включать VPN, когда открываете Tunnely'),
              value: st.connectOnLaunch,
              onChanged: (v) => ctrl.updateSettings(st.copyWith(connectOnLaunch: v)),
            ),
            _Divider(),
            ListTile(
              title: const Text('Маршрутизация'),
              subtitle: Text(st.routing == RoutingMode.ruDirect
                  ? 'Российские сайты напрямую, остальное через VPN'
                  : 'Весь трафик через VPN'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickRouting(context, ref),
            ),
            _Divider(),
            SwitchListTile(
              title: const Text('IPv6'),
              subtitle: const Text('Отключите, если сайты открываются медленно'),
              value: st.ipv6,
              onChanged: (v) => ctrl.updateSettings(st.copyWith(ipv6: v)),
            ),
          ]),
          _Section('Подписки', [
            if (s.subscriptions.isEmpty)
              const ListTile(title: Text('Подписок нет'), subtitle: Text('Добавьте ссылку на подписку через «+»')),
            for (final (i, sub) in s.subscriptions.indexed) ...[
              if (i > 0) _Divider(),
              _SubscriptionTile(sub: sub, refreshing: s.refreshing.contains(sub.id)),
            ],
            if (s.subscriptions.isNotEmpty)
              const ListTile(
                dense: true,
                title: Text('Подписки обновляются автоматически раз в сутки'),
              ),
          ]),
          _Section('Оформление', [
            RadioGroup<ThemeMode>(
              groupValue: st.themeMode,
              onChanged: (v) => ctrl.updateSettings(st.copyWith(themeMode: v)),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(title: Text('Как в системе'), value: ThemeMode.system),
                  RadioListTile<ThemeMode>(title: Text('Тёмная'), value: ThemeMode.dark),
                  RadioListTile<ThemeMode>(title: Text('Светлая'), value: ThemeMode.light),
                ],
              ),
            ),
          ]),
          _Section('Прочее', [
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Журнал работы'),
              subtitle: const Text('События приложения, VPN и ядра — для поиска проблем'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogsScreen())),
            ),
            _Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('О приложении и диагностика'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _pickRouting(BuildContext context, WidgetRef ref) async {
    final st = ref.read(appControllerProvider).settings;
    final v = await showModalBottomSheet<RoutingMode>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<RoutingMode>(
          groupValue: st.routing,
          onChanged: (v) => Navigator.pop(context, v),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<RoutingMode>(
                title: Text('Российские сайты напрямую'),
                subtitle: Text('Банки, Госуслуги и другие сайты РФ работают без VPN. Рекомендуется'),
                value: RoutingMode.ruDirect,
              ),
              RadioListTile<RoutingMode>(
                title: Text('Весь трафик через VPN'),
                subtitle: Text('Все сайты и приложения идут через сервер'),
                value: RoutingMode.global,
              ),
            ],
          ),
        ),
      ),
    );
    if (v != null) await ref.read(appControllerProvider.notifier).updateSettings(st.copyWith(routing: v));
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile({required this.sub, required this.refreshing});
  final Subscription sub;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(appControllerProvider.notifier);
    final parts = <String>[
      if (sub.updatedAt != null) 'обновлено ${formatAgo(sub.updatedAt!)}',
      if (sub.total != null && sub.total! > 0)
        'трафик ${formatBytes((sub.upload ?? 0) + (sub.download ?? 0))} из ${formatBytes(sub.total!)}',
      if (sub.expire != null) 'до ${sub.expire!.day.toString().padLeft(2, '0')}.${sub.expire!.month.toString().padLeft(2, '0')}.${sub.expire!.year}',
      if (sub.isInsecure) 'без HTTPS',
    ];
    return ListTile(
      title: Text(sub.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        sub.lastError ?? parts.join(' · '),
        style: sub.lastError != null ? const TextStyle(color: Brand.danger) : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          refreshing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: 'Обновить',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => ctrl.refreshSubscription(sub.id),
                ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline_rounded, color: Brand.danger),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Удалить подписку?'),
                  content: Text('Подписка «${sub.name}» и все её серверы будут удалены с этого устройства.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Brand.danger),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Удалить'),
                    ),
                  ],
                ),
              );
              if (ok == true) await ctrl.removeSubscription(sub.id);
            },
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title.toUpperCase(), style: inter(12, FontWeight.w700, color: tc.muted, letterSpacing: .6)),
          ),
          Material(
            color: tc.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(indent: 16, endIndent: 16);
}
