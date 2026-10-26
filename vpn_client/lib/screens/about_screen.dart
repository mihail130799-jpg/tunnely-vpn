import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../providers/app_controller.dart';
import '../theme/app_theme.dart';

/// Public source code location required by GPL-3.0. Must be set before the
/// app is distributed (see PROJECT_STATUS.md, "Перед выпуском").
const String? sourceCodeUrl = null;
const appVersion = '0.1.0';

final _coreVersionProvider = FutureProvider<String>((ref) async {
  try {
    return await ref.read(vpnPlatformProvider).coreVersion();
  } catch (_) {
    return 'недоступно';
  }
});

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appControllerProvider);
    final core = ref.watch(_coreVersionProvider).value ?? '…';
    final tc = context.tc;

    final diag = <(String, String)>[
      ('Версия приложения', appVersion),
      ('Ядро', 'Mihomo $core'),
      ('Состояние VPN', s.vpn.status.name),
      ('Серверов', '${s.servers.length}'),
      ('Подписок', '${s.subscriptions.length}'),
      ('Маршрутизация', s.settings.routing.name),
      ('IPv6', s.settings.ipv6 ? 'вкл' : 'выкл'),
      ('Передано за сеанс', '↓ ${formatBytes(s.traffic.totalDown)}  ↑ ${formatBytes(s.traffic.totalUp)}'),
      if (s.vpn.error != null) ('Последняя ошибка', s.vpn.error!),
    ];

    return Scaffold(
      backgroundColor: tc.bgGradient.last,
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/branding/app_icon.png', width: 96, height: 96),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text('Tunnely VPN', style: inter(22, FontWeight.w800, color: tc.onSurface))),
          Center(child: Text('Версия $appVersion', style: inter(13, FontWeight.w500, color: tc.muted))),
          const SizedBox(height: 20),
          Material(
            color: tc.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Диагностика', style: inter(15, FontWeight.w700, color: tc.onSurface)),
                  const SizedBox(height: 8),
                  for (final (k, v) in diag)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(k, style: inter(13, FontWeight.w500, color: tc.muted))),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(v, textAlign: TextAlign.end, style: inter(13, FontWeight.w600, color: tc.onSurface)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Скопировать для поддержки'),
                    onPressed: () {
                      // Contains no keys, server addresses or subscription URLs.
                      Clipboard.setData(ClipboardData(text: diag.map((e) => '${e.$1}: ${e.$2}').join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: tc.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Конфиденциальность', style: inter(15, FontWeight.w700, color: tc.onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    'Tunnely не собирает аналитику и не отправляет ваши ключи третьим лицам. '
                    'Ключи и подписки хранятся только на этом устройстве в зашифрованном виде.',
                    style: inter(13, FontWeight.w500, color: tc.muted),
                  ),
                  const SizedBox(height: 14),
                  Text('Лицензия', style: inter(15, FontWeight.w700, color: tc.onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    'Tunnely — свободная программа под лицензией GNU GPL v3. '
                    'Исходный код: ${sourceCodeUrl ?? 'ссылка будет добавлена перед выпуском'}\n'
                    'Используется ядро Mihomo (MIT) и библиотеки sing (GPL-3.0).',
                    style: inter(13, FontWeight.w500, color: tc.muted),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'Tunnely VPN',
                      applicationVersion: appVersion,
                    ),
                    child: const Text('Лицензии компонентов'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
