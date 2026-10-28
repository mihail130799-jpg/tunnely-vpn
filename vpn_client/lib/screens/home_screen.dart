import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../models/server_profile.dart';
import '../providers/app_controller.dart';
import '../services/vpn_platform.dart';
import '../theme/app_theme.dart';
import '../widgets/server_widgets.dart';
import '../widgets/tunnel_button.dart';
import 'import_sheet.dart';
import 'servers_panel.dart';
import 'settings_screen.dart';
import 'update_widgets.dart';

/// Concept C "Light in the tunnel": full-screen gradient, tunnel button,
/// timer + speeds, and a draggable bottom panel with servers and import.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.read(appControllerProvider).vpn.status == VpnStatus.connected) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appControllerProvider);
    final tc = context.tc;
    final size = MediaQuery.sizeOf(context);
    final tunnelSize = (size.width * .68).clamp(200.0, 320.0);

    ref.listen(appControllerProvider.select((s) => s.message), (prev, next) {
      if (next == null || next.id == prev?.id) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(next.text),
          backgroundColor: next.isError ? const Color(0xFF7A1F2B) : null,
          duration: Duration(seconds: next.isError ? 7 : 3),
          showCloseIcon: next.isError,
        ));
    });

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.44),
            radius: 1.2,
            colors: tc.bgGradient,
            stops: const [0, .38, .75],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _TopBar(state: s),
                  const UpdateBanner(),
                  SizedBox(height: size.height * .03),
                  TunnelButton(
                    status: s.vpn.status,
                    size: tunnelSize,
                    onTap: () => ref.read(appControllerProvider.notifier).toggle(),
                  ),
                  const SizedBox(height: 18),
                  _StatusBlock(state: s),
                ],
              ),
            ),
            const ServersPanel(),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tc = context.tc;
    final sel = state.selected;
    final deadServer = state.vpn.status == VpnStatus.connected && state.latency[sel?.id ?? autoLatencyKey] == -1;
    final (label, dot) = switch (state.vpn.status) {
      VpnStatus.connected when deadServer => ('Сервер не отвечает', Brand.warning),
      VpnStatus.connected => ('Защищено', Brand.success),
      VpnStatus.connecting => ('Подключение…', Brand.cyan),
      VpnStatus.reconnecting => ('Переподключение…', Brand.cyan),
      VpnStatus.disconnecting => ('Отключение…', tc.muted),
      VpnStatus.error => ('Ошибка', Brand.danger),
      VpnStatus.disconnected => ('Не защищено', Brand.warning),
    };
    final pillBg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: .1)
        : Brand.blue.withValues(alpha: .1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(99)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(color: dot, pulsing: state.vpn.isBusy),
                const SizedBox(width: 6),
                Text(label, style: inter(12, FontWeight.w600, color: tc.onSurface)),
              ],
            ),
          ),
          const Spacer(),
          _RoundButton(
            icon: Icons.add_rounded,
            tooltip: 'Добавить ключ',
            onTap: () => showImportSheet(context),
            bg: pillBg,
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: Icons.settings_outlined,
            tooltip: 'Настройки',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            bg: pillBg,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.bg, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: context.tc.accent)),
          ),
        ),
      );
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.pulsing) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .3, end: 1.0).animate(_c),
        child: Container(width: 7, height: 7, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      );
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final v = state.vpn;
    final String big;
    final String small;
    switch (v.status) {
      case VpnStatus.connected:
        big = formatDuration(DateTime.now().difference(v.connectedSince ?? DateTime.now()));
        small = '';
      case VpnStatus.connecting:
      case VpnStatus.reconnecting:
        big = 'Подключение';
        small = 'Устанавливаем защищённый туннель…';
      case VpnStatus.disconnecting:
        big = 'Отключение';
        small = '';
      case VpnStatus.error:
        big = 'Подключить';
        small = v.error ?? 'Не удалось подключиться';
      case VpnStatus.disconnected:
        big = 'Подключить';
        small = state.servers.isEmpty ? 'Добавьте ключ, чтобы начать' : 'Нажмите на туннель';
    }
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(big, key: ValueKey(big.length > 8 ? big : 'timer'),
              style: inter(34, FontWeight.w800, color: tc.onSurface, letterSpacing: -.7, tabular: true)),
        ),
        const SizedBox(height: 4),
        if (v.status == VpnStatus.connected)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward_rounded, size: 14, color: tc.muted),
              Text(' ${formatSpeed(state.traffic.down)}', style: inter(12, FontWeight.w500, color: tc.muted, tabular: true)),
              const SizedBox(width: 14),
              Icon(Icons.arrow_upward_rounded, size: 14, color: tc.muted),
              Text(' ${formatSpeed(state.traffic.up)}', style: inter(12, FontWeight.w500, color: tc.muted, tabular: true)),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(small, textAlign: TextAlign.center, maxLines: 3,
                style: inter(12, FontWeight.w500, color: v.status == VpnStatus.error ? Brand.danger : tc.muted)),
          ),
        if (v.status == VpnStatus.connected) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(state.settings.foreignOnly ? Icons.public_rounded : Icons.vpn_lock_rounded, size: 13, color: tc.muted),
              const SizedBox(width: 4),
              Text(
                state.settings.foreignOnly ? 'Только зарубежные сервисы через VPN' : 'Весь трафик через VPN',
                style: inter(12, FontWeight.w500, color: tc.muted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Current server row used at the top of the bottom panel.
class CurrentServerRow extends StatelessWidget {
  const CurrentServerRow({super.key, required this.server, required this.latency, required this.onTap});
  final ServerProfile? server;
  final int? latency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    final s = server;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            FlagBadge(code: s?.countryCode, auto: s == null, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s == null ? 'Авто: самый быстрый' : serverTitle(s),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(15, FontWeight.w700, color: tc.onSurface)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(s == null ? 'Сервер выбирается автоматически' : s.protocolLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(12, FontWeight.w500, color: tc.muted)),
                      ),
                      if (latency != null) ...[const Text('  ·  '), PingLabel(latency)],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_less_rounded, color: tc.muted),
          ],
        ),
      ),
    );
  }
}
