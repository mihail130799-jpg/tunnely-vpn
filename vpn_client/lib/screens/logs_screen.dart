import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_controller.dart';
import '../services/app_log.dart';
import '../theme/app_theme.dart';

/// In-app log: application events, VPN service events and the Xray core log.
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String _app = '', _service = '', _core = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final app = await AppLog.instance.read();
    var service = '', core = '';
    try {
      final n = await ref.read(vpnPlatformProvider).logs();
      service = n.events;
      core = n.core;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _app = app;
      _service = service;
      _core = core;
      _loading = false;
    });
  }

  Future<void> _copyAll() async {
    final text = await ref.read(appControllerProvider.notifier).fullLog();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Журнал скопирован')));
    }
  }

  Future<void> _clear() async {
    await ref.read(appControllerProvider.notifier).clearLogs();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final st = ref.watch(appControllerProvider.select((s) => s.settings));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: tc.bgGradient.last,
        appBar: AppBar(
          title: const Text('Журнал работы'),
          actions: [
            IconButton(tooltip: 'Обновить', icon: const Icon(Icons.refresh_rounded), onPressed: _reload),
            IconButton(tooltip: 'Скопировать всё', icon: const Icon(Icons.copy_all_rounded), onPressed: _copyAll),
            IconButton(tooltip: 'Очистить', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear),
          ],
          bottom: TabBar(
            labelColor: tc.accent,
            unselectedLabelColor: tc.muted,
            indicatorColor: tc.accent,
            tabs: const [Tab(text: 'Приложение'), Tab(text: 'VPN-служба'), Tab(text: 'Ядро Xray')],
          ),
        ),
        body: Column(
          children: [
            SwitchListTile(
              title: const Text('Подробный журнал ядра'),
              subtitle: const Text('Включайте при проблемах. Применится при следующем подключении'),
              value: st.verboseLogs,
              onChanged: (v) => ref.read(appControllerProvider.notifier).updateSettings(st.copyWith(verboseLogs: v)),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(children: [_LogView(_app), _LogView(_service), _LogView(_core)]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'Журнал хранится только на этом устройстве. Ключи и ссылки подписок в него не записываются; '
                'в подробном режиме ядро записывает адреса сайтов.',
                style: inter(11, FontWeight.w500, color: tc.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final lines = text.trim().isEmpty ? const <String>[] : text.trim().split('\n').reversed.toList();
    if (lines.isEmpty) {
      return Center(child: Text('Пока пусто', style: inter(14, FontWeight.w500, color: tc.muted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final l = lines[i];
        final bad = l.contains('[error]') || l.toLowerCase().contains('fail') || l.contains('[Error]') ||
            l.contains('[Warning]') || l.contains('ошибка');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText(
            l,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.3,
              color: bad ? Brand.danger : tc.onSurface,
            ),
          ),
        );
      },
    );
  }
}
