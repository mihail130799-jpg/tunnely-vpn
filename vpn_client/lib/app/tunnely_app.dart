import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../providers/app_controller.dart';
import '../screens/home_screen.dart';
import '../theme/app_theme.dart';

class TunnelyApp extends ConsumerStatefulWidget {
  const TunnelyApp({super.key, this.handleLinks = true});

  /// Disabled in widget tests where the app_links plugin is unavailable.
  final bool handleLinks;

  @override
  ConsumerState<TunnelyApp> createState() => _TunnelyAppState();
}

class _TunnelyAppState extends ConsumerState<TunnelyApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    unawaited(initializeDateFormatting('ru'));
    final ctrl = ref.read(appControllerProvider.notifier);
    unawaited(ctrl.init());
    if (widget.handleLinks) {
      // tunnely://..., vless://..., trojan://... opened from Telegram, browser or a QR app.
      _links = AppLinks().uriLinkStream.listen((uri) => ctrl.importText(uri.toString()));
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appControllerProvider.select((s) => s.settings.themeMode));
    return MaterialApp(
      title: 'Tunnely',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeScreen(),
    );
  }
}
