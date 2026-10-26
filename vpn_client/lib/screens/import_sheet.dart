import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_controller.dart';
import '../theme/app_theme.dart';
import 'qr_scanner_screen.dart';

/// Imports from the clipboard (the main path: one tap).
Future<void> importFromClipboard(BuildContext context, WidgetRef ref) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  await ref.read(appControllerProvider.notifier).importText(data?.text ?? '');
}

Future<void> importFromQr(BuildContext context, WidgetRef ref) async {
  final code = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const QrScannerScreen(), fullscreenDialog: true),
  );
  if (code != null) await ref.read(appControllerProvider.notifier).importText(code);
}

Future<void> importFromFile(WidgetRef ref) async {
  final ctrl = ref.read(appControllerProvider.notifier);
  final files = await FilePicker.pickFiles();
  if (files.isEmpty) return;
  final bytes = await files.first.readAsBytes();
  if (bytes.length > 2 * 1024 * 1024) {
    ctrl.showMessage('Файл слишком большой для ключей', error: true);
    return;
  }
  await ctrl.importText(utf8.decode(bytes, allowMalformed: true));
}

/// Bottom sheet with every import method plus a text field for manual paste.
Future<void> showImportSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImportSheet(),
    );

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet();

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Добавить ключ или подписку', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Ключ VPN или ссылку на подписку вы получаете от своего провайдера.',
                style: inter(13, FontWeight.w500, color: tc.muted)),
            const SizedBox(height: 16),
            _Action(
              icon: Icons.content_paste_rounded,
              title: 'Вставить из буфера',
              subtitle: 'Скопируйте ключ или ссылку и нажмите сюда',
              primary: true,
              onTap: _busy ? null : () => _run(() => importFromClipboard(context, ref)),
            ),
            _Action(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Сканировать QR-код',
              onTap: _busy ? null : () => _run(() => importFromQr(context, ref)),
            ),
            _Action(
              icon: Icons.description_outlined,
              title: 'Открыть файл',
              subtitle: 'Текстовый файл с ключами или конфигурацией',
              onTap: _busy ? null : () => _run(() => importFromFile(ref)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'vless://…  или  https://…'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => ref.read(appControllerProvider.notifier).importText(_text.text)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, this.subtitle, this.onTap, this.primary = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tc.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: primary ? const LinearGradient(colors: [Brand.blue, Brand.cyan]) : null,
                    color: primary ? null : tc.surface,
                  ),
                  child: Icon(icon, color: primary ? Colors.white : tc.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: inter(15, FontWeight.w600, color: tc.onSurface)),
                      if (subtitle != null) Text(subtitle!, style: inter(12, FontWeight.w500, color: tc.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: tc.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
