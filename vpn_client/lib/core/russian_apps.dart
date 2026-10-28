/// Russian apps that work directly (outside the tunnel) in the
/// "foreign services only" mode.
///
/// Many Russian banking and government apps refuse to work when they see a
/// VPN; apps excluded from the tunnel do not see it at all.
library;

/// Known Russian apps whose package names do not start with `ru.`
/// (plus well-known `ru.` ones for documentation and tests).
const knownRussianApps = <String>{
  // Banks and payments
  'ru.sberbankmobile', 'com.idamob.tinkoff.android', 'ru.tinkoff.investing', 'ru.vtb24.mobilebanking.android',
  'ru.alfabank.mobile.android', 'ru.raiffeisen.mobile.new', 'ru.gazprombank.android.mobilebank.app',
  'ru.rshb.dbo', 'ru.sovcomcard.halva.v1', 'ru.mts.money', 'ru.ozon.fintech.finance', 'com.openbank',
  'ru.psbank.online', 'ru.nspk.mirpay', 'ru.nspk.sbpay', 'com.yandex.bank', 'ru.pochtabank.mobile',
  // Government
  'ru.rostel', 'ru.gosuslugi.goskey', 'ru.fns.lkfl', 'ru.altarix.mos.pgu', 'ru.mos.app',
  // Social, messengers, media
  'com.vkontakte.android', 'com.vk.im', 'com.vk.vkvideo', 'ru.ok.android', 'ru.oneme.app', 'ru.mail.mailapp',
  'ru.mail.cloud', 'ru.rutube.app', 'ru.kinopoisk', 'ru.more.play', 'ru.ivi.client', 'com.zvooq.openplay',
  'ru.yandex.music', 'ru.zen.android',
  // Yandex
  'ru.yandex.searchplugin', 'com.yandex.browser', 'ru.yandex.taxi', 'ru.yandex.yandexmaps', 'ru.yandex.yandexnavi',
  'ru.yandex.market', 'ru.yandex.disk', 'ru.yandex.mail', 'ru.yandex.translate', 'ru.foodfox.client',
  'ru.yandex.metro', 'ru.yandex.weatherplugin',
  // Marketplaces, shopping, delivery
  'ru.ozon.app.android', 'com.wildberries.ru', 'com.avito.android', 'ru.megamarket.marketplace', 'ru.lamoda',
  'ru.instamart', 'ru.tander.magnit', 'ru.lenta.lentochka', 'ru.vkusvill', 'ru.dodopizza.app',
  // Carriers
  'ru.mts.mymts', 'ru.megafon.mlk', 'ru.beeline.services', 'ru.tele2.mytele2',
  // Transport, maps, services
  'ru.rzd.pass', 'ru.aeroflot', 'ru.dublgis.dgismobile', 'ru.mosmetro.metro', 'ru.vk.store', 'ru.hh.android',
  'ru.domclick.mortgage', 'ru.cian.main', 'com.octopod.russianpost.client.android',
};

/// True for apps treated as Russian: the curated list, or a `ru.` package
/// name (the convention virtually all Russian developers follow).
bool isRussianApp(String package) => knownRussianApps.contains(package) || package.startsWith('ru.');

/// Packages that bypass the tunnel.
///
/// [installed] — launcher apps on the device; [autoRussian] — whether the
/// "Russian apps without VPN" switch is on (only in foreign-only mode);
/// [alwaysDirect] / [alwaysVpn] — the user's manual choices, which win.
Set<String> bypassPackages({
  required Iterable<String> installed,
  required bool autoRussian,
  required Set<String> alwaysDirect,
  required Set<String> alwaysVpn,
  String ownPackage = 'com.tunnely.vpn',
}) {
  final out = <String>{
    if (autoRussian) ...installed.where(isRussianApp),
    ...alwaysDirect,
  }..removeAll(alwaysVpn);
  out.remove(ownPackage);
  return out;
}
