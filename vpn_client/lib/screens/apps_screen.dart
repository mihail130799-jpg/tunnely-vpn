import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/russian_apps.dart';
import '../providers/app_controller.dart';
import '../services/vpn_platform.dart';
import '../theme/app_theme.dart';

final _installedAppsProvider = FutureProvider.autoDispose<List<InstalledApp>>(
  (ref) => ref.read(vpnPlatformProvider).installedApps(),
);

/// Per-app choice: work through the VPN or directly.
class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  String _query = '';
  bool _showSystem = false;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final settings = ref.watch(appControllerProvider.select((s) => s.settings));
    final ctrl = ref.read(appControllerProvider.notifier);
    final apps = ref.watch(_installedAppsProvider);
    final connected = ref.watch(appControllerProvider.select((s) => s.vpn.isOn));

    return Scaffold(
      backgroundColor: tc.bgGradient.last,
      appBar: AppBar(title: const Text('Приложения без VPN')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              settings.foreignOnly && settings.russianAppsDirect
                  ? 'Отмеченные приложения работают напрямую, без VPN. Российские отмечены автоматически — '
                      'любое можно переключить.'
                  : 'Отмеченные приложения работают напрямую, без VPN. Остальные — через VPN.',
              style: inter(13, FontWeight.w500, color: tc.muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Поиск приложения', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Показывать системные'),
            value: _showSystem,
            onChanged: (v) => setState(() => _showSystem = v),
          ),
          if (connected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Изменения применяются сразу — VPN переподключится на секунду.',
                  style: inter(12, FontWeight.w500, color: tc.accent)),
            ),
          Expanded(
            child: apps.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Не удалось получить список приложений: $e')),
              data: (list) {
                final shown = list
                    .where((a) => _showSystem || !a.system || ctrl.appIsDirect(a.package))
                    .where((a) =>
                        _query.isEmpty || a.label.toLowerCase().contains(_query) || a.package.contains(_query))
                    .toList()
                  // Direct apps first, then alphabetically.
                  ..sort((a, b) {
                    final da = ctrl.appIsDirect(a.package), db = ctrl.appIsDirect(b.package);
                    if (da != db) return da ? -1 : 1;
                    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
                  });
                if (shown.isEmpty) {
                  final hint = !_showSystem && _query.isEmpty && list.isNotEmpty
                      ? 'Есть только системные приложения — включите «Показывать системные»'
                      : 'Ничего не найдено';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(hint, textAlign: TextAlign.center, style: inter(14, FontWeight.w500, color: tc.muted)),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final a = shown[i];
                    final direct = ctrl.appIsDirect(a.package);
                    final russian = isRussianApp(a.package);
                    return SwitchListTile(
                      secondary: a.icon != null
                          ? Image.memory(a.icon!, width: 36, height: 36, gaplessPlayback: true)
                          : const Icon(Icons.android_rounded, size: 36),
                      title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        direct ? (russian ? 'Без VPN · российское' : 'Без VPN') : 'Через VPN',
                        style: inter(12, FontWeight.w500, color: direct ? Brand.success : tc.muted),
                      ),
                      value: direct,
                      onChanged: (v) async {
                        await ctrl.setAppDirect(a.package, v);
                        if (mounted) setState(() {});
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
