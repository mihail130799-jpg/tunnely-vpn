import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../providers/app_controller.dart';
import '../theme/app_theme.dart';

/// Public source code location required by GPL-3.0.
const sourceCodeUrl = 'https://github.com/mihail130799-jpg/tunnely-vpn';
const appVersion = '0.2.0';

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
      ('Ядро', 'Xray $core'),
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
                  const _DiagnosticsButton(),
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
                    'Исходный код: $sourceCodeUrl\n'
                    'Используется ядро Xray-core (MPL-2.0).',
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

/// Runs a real check of every server and copies a support report
/// (no keys, passwords or subscription URLs) to the clipboard.
class _DiagnosticsButton extends ConsumerStatefulWidget {
  const _DiagnosticsButton();

  @override
  ConsumerState<_DiagnosticsButton> createState() => _DiagnosticsButtonState();
}

class _DiagnosticsButtonState extends ConsumerState<_DiagnosticsButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final report = await ref.read(appControllerProvider.notifier).diagnosticsReport();
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отчёт скопирован — отправьте его в поддержку')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.network_check_rounded, size: 18),
        label: Text(_busy ? 'Проверяем серверы…' : 'Проверить соединение и скопировать отчёт'),
        onPressed: _busy ? null : _run,
      );
}
