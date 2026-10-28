import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../providers/update_controller.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

/// "Обновление приложения" block for the settings screen.
class UpdateTiles extends ConsumerWidget {
  const UpdateTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(updateControllerProvider);
    final ctrl = ref.read(updateControllerProvider.notifier);
    final tc = context.tc;
    final info = u.info;

    final subtitle = switch (u.status) {
      UpdateStatus.checking => 'Проверяем…',
      UpdateStatus.upToDate => 'Установлена последняя версия',
      UpdateStatus.error => u.error ?? 'Не удалось проверить',
      _ when info != null => 'Доступна версия ${info.version}',
      _ when u.lastCheck != null => 'Проверено ${formatAgo(u.lastCheck!)}',
      _ => 'Проверяется автоматически раз в сутки',
    };

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_rounded),
          title: Text('Версия ${u.current.isEmpty ? '…' : u.current}'),
          subtitle: Text(subtitle, style: u.status == UpdateStatus.error ? const TextStyle(color: Brand.danger) : null),
          trailing: u.status == UpdateStatus.checking
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: u.busy ? null : () => ctrl.check(),
                  child: const Text('Проверить'),
                ),
        ),
        if (info != null) ...[
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (info.notes.trim().isNotEmpty) ...[
                  Text('Что нового в ${info.version}', style: inter(14, FontWeight.w700, color: tc.onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    _plainNotes(info.notes),
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                    style: inter(13, FontWeight.w500, color: tc.muted),
                  ),
                  const SizedBox(height: 12),
                ],
                if (u.status == UpdateStatus.downloading) ...[
                  LinearProgressIndicator(value: u.progress > 0 ? u.progress : null),
                  const SizedBox(height: 6),
                  Text(
                    'Загрузка ${(u.progress * 100).round()}% из ${formatBytes(info.size)}',
                    style: inter(12, FontWeight.w500, color: tc.muted),
                  ),
                ] else
                  FilledButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: Text(switch (u) {
                      _ when u.status == UpdateStatus.installing => 'Открываем установщик…',
                      _ when u.downloaded => 'Установить ${info.version}',
                      _ => 'Скачать и установить (${formatBytes(info.size)})',
                    }),
                    onPressed: u.busy ? null : ctrl.downloadAndInstall,
                  ),
                if (u.error != null && u.status != UpdateStatus.error) ...[
                  const SizedBox(height: 8),
                  Text(u.error!, style: inter(12, FontWeight.w600, color: Brand.danger)),
                ],
                const SizedBox(height: 6),
                Text(
                  'Файл скачивается с GitHub и проверяется по контрольной сумме. '
                  'Android попросит подтвердить установку; ключи и настройки сохранятся.',
                  style: inter(11, FontWeight.w500, color: tc.muted),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Release notes are Markdown; show them as plain text.
  static String _plainNotes(String md) => md
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^#+\s*'), '').replaceFirst(RegExp(r'^\s*[-*]\s+'), '• '))
      .join('\n')
      .replaceAll('**', '')
      .replaceAll('`', '')
      .trim();
}

/// Small banner on the home screen when a new version is available.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateControllerProvider.select((u) => u.info));
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: Brand.blue.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded, size: 20, color: context.tc.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Доступна новая версия ${info.version}',
                    style: inter(13, FontWeight.w600, color: context.tc.onSurface),
                  ),
                ),
                Text('Обновить', style: inter(13, FontWeight.w700, color: context.tc.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
