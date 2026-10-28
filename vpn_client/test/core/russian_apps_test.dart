import 'package:flutter_test/flutter_test.dart';
import 'package:tunnely/core/russian_apps.dart';
import 'package:tunnely/models/app_settings.dart';
import 'package:tunnely/core/xray_config.dart';

void main() {
  group('isRussianApp', () {
    test('curated non-ru packages', () {
      expect(isRussianApp('com.vkontakte.android'), true);
      expect(isRussianApp('com.idamob.tinkoff.android'), true);
      expect(isRussianApp('com.wildberries.ru'), true);
    });
    test('ru. prefix', () {
      expect(isRussianApp('ru.sberbankmobile'), true);
      expect(isRussianApp('ru.some.newbank'), true);
    });
    test('foreign apps', () {
      expect(isRussianApp('com.google.android.youtube'), false);
      expect(isRussianApp('org.telegram.messenger'), false);
      expect(isRussianApp('com.instagram.android'), false);
    });
  });

  group('bypassPackages', () {
    const installed = ['ru.sberbankmobile', 'com.vkontakte.android', 'com.google.android.youtube', 'org.telegram.messenger'];

    test('foreign-only mode excludes installed Russian apps', () {
      expect(
        bypassPackages(installed: installed, autoRussian: true, alwaysDirect: {}, alwaysVpn: {}),
        {'ru.sberbankmobile', 'com.vkontakte.android'},
      );
    });

    test('manual choices win over the automatic rule', () {
      expect(
        bypassPackages(
          installed: installed,
          autoRussian: true,
          alwaysDirect: {'org.telegram.messenger'},
          alwaysVpn: {'com.vkontakte.android'},
        ),
        {'ru.sberbankmobile', 'org.telegram.messenger'},
      );
    });

    test('without the automatic rule only manual choices apply', () {
      expect(
        bypassPackages(installed: installed, autoRussian: false, alwaysDirect: {'ru.x'}, alwaysVpn: {}),
        {'ru.x'},
      );
    });

    test('own package is never excluded', () {
      expect(
        bypassPackages(installed: const [], autoRussian: false, alwaysDirect: {'com.tunnely.vpn'}, alwaysVpn: {}),
        isEmpty,
      );
    });
  });

  test('settings round-trip keeps app choices', () {
    const s = AppSettings(
      routing: RoutingMode.ruDirect,
      russianAppsDirect: false,
      alwaysDirectApps: {'a.b'},
      alwaysVpnApps: {'ru.c'},
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.russianAppsDirect, false);
    expect(back.alwaysDirectApps, {'a.b'});
    expect(back.alwaysVpnApps, {'ru.c'});
    expect(back.foreignOnly, true);
    expect(const AppSettings().russianAppsDirect, true, reason: 'on by default');
  });
}
