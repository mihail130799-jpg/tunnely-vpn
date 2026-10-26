import 'package:flutter/material.dart';

import '../core/country.dart';
import '../core/format.dart';
import '../models/server_profile.dart';
import '../theme/app_theme.dart';

/// Round flag; falls back to a globe for unknown countries and a bolt for Auto.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, this.code, this.size = 34, this.auto = false});

  final String? code;
  final double size;
  final bool auto;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    Widget child;
    if (auto) {
      child = Icon(Icons.bolt_rounded, size: size * .6, color: Colors.white);
    } else if (code != null) {
      child = Text(flagEmoji(code!), style: TextStyle(fontSize: size * .95, height: 1.1));
    } else {
      child = Icon(Icons.public_rounded, size: size * .62, color: tc.muted);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: auto ? null : tc.surfaceVariant,
        gradient: auto ? const LinearGradient(colors: [Brand.blue, Brand.cyan]) : null,
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: FittedBox(child: child),
    );
  }
}

/// Latency label colored by quality; empty when unknown.
class PingLabel extends StatelessWidget {
  const PingLabel(this.ms, {super.key, this.testing = false});

  final int? ms;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    if (ms == null) {
      return testing
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: context.tc.muted))
          : const SizedBox.shrink();
    }
    final v = ms!;
    final (text, color) = v < 0
        ? ('нет связи', Brand.danger)
        : ('$v мс', v < 100 ? Brand.success : (v < 250 ? Brand.warning : Brand.danger));
    return Text(text, style: inter(12, FontWeight.w600, color: color));
  }
}

/// Display title for a server: country in Russian when the name is only a code/flag.
String serverTitle(ServerProfile s) {
  final name = s.name.trim();
  final code = s.countryCode;
  final stripped = name.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '').trim();
  if (stripped.isEmpty && code != null) return countryNamesRu[code] ?? code;
  return stripped.isEmpty ? name : stripped;
}

class ServerTile extends StatelessWidget {
  const ServerTile({
    super.key,
    required this.server,
    required this.selected,
    required this.onTap,
    this.latency,
    this.testing = false,
    this.onLongPress,
  });

  final ServerProfile server;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int? latency;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Material(
      color: selected ? tc.accent.withValues(alpha: .12) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              FlagBadge(code: server.countryCode),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(serverTitle(server), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: inter(15, FontWeight.w600, color: tc.onSurface)),
                    const SizedBox(height: 2),
                    Text(server.protocolLabel, maxLines: 1, style: inter(12, FontWeight.w500, color: tc.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PingLabel(latency, testing: testing),
              const SizedBox(width: 8),
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
