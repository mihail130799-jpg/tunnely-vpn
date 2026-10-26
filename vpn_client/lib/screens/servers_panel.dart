import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../models/server_profile.dart';
import '../models/subscription.dart';
import '../providers/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/server_widgets.dart';
import 'home_screen.dart';
import 'import_sheet.dart';

/// Draggable bottom panel: current server, quick chips, import buttons;
/// dragged up it becomes the full server list with search.
class ServersPanel extends ConsumerStatefulWidget {
  const ServersPanel({super.key});

  @override
  ConsumerState<ServersPanel> createState() => _ServersPanelState();
}

class _ServersPanelState extends ConsumerState<ServersPanel> {
  final _sheet = DraggableScrollableController();
  String _query = '';

  static const _min = .30;
  static const _max = .92;

  void _expand() => _sheet.animateTo(_max, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  void _collapse() =>
      _sheet.animateTo(_min, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);

  Future<void> _pick(String? id) async {
    await ref.read(appControllerProvider.notifier).select(id);
    if (_sheet.isAttached && _sheet.size > _min + .05) _collapse();
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appControllerProvider);
    final tc = context.tc;
    final ctrl = ref.read(appControllerProvider.notifier);

    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: _min,
      minChildSize: _min,
      maxChildSize: _max,
      snap: true,
      builder: (context, scroll) => DecoratedBox(
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -10))],
        ),
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: tc.muted.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (s.servers.isEmpty)
                      _EmptyHint()
                    else ...[
                      CurrentServerRow(
                        server: s.selected,
                        latency: s.selected == null ? null : s.latency[s.selected!.id],
                        onTap: _expand,
                      ),
                      const SizedBox(height: 10),
                      _QuickChips(state: s, onPick: _pick),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _PanelButton(
                            icon: Icons.content_paste_rounded,
                            label: 'Из буфера',
                            primary: true,
                            onTap: () => importFromClipboard(context, ref),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PanelButton(
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'QR-код',
                            onTap: () => importFromQr(context, ref),
                          ),
                        ),
                      ],
                    ),
                    if (s.servers.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Серверы', style: inter(17, FontWeight.w700, color: tc.onSurface)),
                          ),
                          IconButton(
                            tooltip: 'Проверить задержку',
                            onPressed: s.testing ? null : ctrl.testLatency,
                            icon: s.testing
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(Icons.speed_rounded, color: tc.accent),
                          ),
                          if (s.subscriptions.isNotEmpty)
                            IconButton(
                              tooltip: 'Обновить подписки',
                              onPressed: s.refreshing.isNotEmpty ? null : ctrl.refreshAllSubscriptions,
                              icon: Icon(Icons.refresh_rounded, color: tc.accent),
                            ),
                        ],
                      ),
                      if (s.servers.length > 6)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                            decoration: const InputDecoration(
                              hintText: 'Поиск сервера',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (s.servers.isNotEmpty) ..._serverSlivers(context, s),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _serverSlivers(BuildContext context, AppState s) {
    bool match(ServerProfile p) =>
        _query.isEmpty || p.name.toLowerCase().contains(_query) || serverTitle(p).toLowerCase().contains(_query);

    final groups = <(Subscription?, List<ServerProfile>)>[
      for (final sub in s.subscriptions) (sub, s.servers.where((p) => p.subscriptionId == sub.id && match(p)).toList()),
      (null, s.servers.where((p) => p.subscriptionId == null && match(p)).toList()),
    ];

    return [
      if (_query.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _AutoTile(selected: s.isAuto, onTap: () => _pick(null)),
          ),
        ),
      for (final (sub, items) in groups)
        if (items.isNotEmpty || (sub != null && _query.isEmpty)) ...[
          SliverToBoxAdapter(child: _GroupHeader(sub: sub, count: items.length, refreshing: sub != null && s.refreshing.contains(sub.id))),
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final p = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ServerTile(
                  server: p,
                  selected: s.selectedId == p.id,
                  latency: s.latency[p.id],
                  testing: s.testing,
                  onTap: () => _pick(p.id),
                  onLongPress: () => _serverMenu(context, p),
                ),
              );
            },
          ),
        ],
    ];
  }

  Future<void> _serverMenu(BuildContext context, ServerProfile p) async {
    final ctrl = ref.read(appControllerProvider.notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(serverTitle(p), style: inter(16, FontWeight.w700)), subtitle: Text(p.protocolLabel)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (p.subscriptionId == null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Brand.danger),
                title: const Text('Удалить', style: TextStyle(color: Brand.danger)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'delete') await ctrl.removeServer(p.id);
    if (action == 'rename') {
      if (!context.mounted) return;
      final name = await _askName(context, p.name);
      if (name != null) await ctrl.renameServer(p.id, name);
    }
  }
}

Future<String?> _askName(BuildContext context, String current) {
  final c = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Название сервера'),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить')),
      ],
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Пока нет серверов', style: inter(15, FontWeight.w700, color: tc.onSurface)),
        const SizedBox(height: 4),
        Text(
          'Скопируйте ключ или ссылку на подписку, которую вам прислали, и нажмите «Из буфера». Или отсканируйте QR-код.',
          style: inter(13, FontWeight.w500, color: tc.muted),
        ),
      ],
    );
  }
}

class _QuickChips extends StatelessWidget {
  const _QuickChips({required this.state, required this.onPick});
  final AppState state;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    // Fastest known first, then the rest in list order; current choice excluded.
    final items = state.servers.where((s) => s.id != state.selectedId).toList()
      ..sort((a, b) {
        final la = state.latency[a.id], lb = state.latency[b.id];
        int rank(int? v) => v == null || v < 0 ? 1 << 30 : v;
        return rank(la).compareTo(rank(lb));
      });
    final chips = <Widget>[
      if (!state.isAuto) _Chip(label: 'Авто', leading: const FlagBadge(auto: true, size: 22), onTap: () => onPick(null)),
      for (final s in items.take(8))
        _Chip(label: serverTitle(s), leading: FlagBadge(code: s.countryCode, size: 22), onTap: () => onPick(s.id)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.leading, required this.onTap});
  final String label;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Material(
      color: tc.surfaceVariant,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: inter(12, FontWeight.w600, color: tc.onSurface)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final fg = primary ? Colors.white : tc.onSurface;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: primary ? const LinearGradient(colors: [Brand.blue, Brand.cyan]) : null,
          color: primary ? null : tc.surfaceVariant,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(label, style: inter(13, FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoTile extends StatelessWidget {
  const _AutoTile({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Material(
      color: selected ? tc.accent.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const FlagBadge(auto: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Авто', style: inter(15, FontWeight.w600, color: tc.onSurface)),
                    Text('Самый быстрый сервер, переключается сам', style: inter(12, FontWeight.w500, color: tc.muted)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? tc.accent : tc.muted.withValues(alpha: .5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({required this.sub, required this.count, required this.refreshing});
  final Subscription? sub;
  final int count;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = context.tc;
    final s = sub;
    final subtitle = s == null
        ? 'Добавлены вручную · $count'
        : s.lastError != null
            ? s.lastError!
            : 'обновлено ${s.updatedAt == null ? '—' : formatAgo(s.updatedAt!)} · $count';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s?.name ?? 'Мои ключи', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: inter(13, FontWeight.w700, color: tc.onSurface)),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: inter(11, FontWeight.w500, color: s?.lastError != null ? Brand.danger : tc.muted)),
              ],
            ),
          ),
          if (s != null)
            refreshing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Обновить',
                    icon: Icon(Icons.refresh_rounded, size: 20, color: tc.accent),
                    onPressed: () => ref.read(appControllerProvider.notifier).refreshSubscription(s.id),
                  ),
        ],
      ),
    );
  }
}
