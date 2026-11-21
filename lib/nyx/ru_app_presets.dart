/// МехаВПН: готовый набор приложений, которые часто отказываются работать через VPN
/// (банки, госсервисы, маркетплейсы). Один тап добавляет установленные из них
/// в режим «Bypass» — то есть они ходят в интернет напрямую, мимо туннеля.
///
/// Пакеты, которых нет на телефоне, просто не добавляются, поэтому список можно
/// держать шире, чем реально нужно конкретному пользователю.
///
/// ВАЖНО: пакеты — это идентификаторы из Google Play / RuStore. Если приложение
/// сменило id, строка перестанет совпадать; на работу остальных это не влияет.
abstract final class NyxRuPresets {
  /// package name → название для интерфейса.
  static const apps = <String, String>{
    // Госуслуги и налоги
    'ru.rostel': 'Госуслуги',
    'com.gnivts.selfemployed': 'Мой налог',

    // Соцсети и почта
    'com.vkontakte.android': 'ВКонтакте',
    'ru.ok.android': 'Одноклассники',
    'ru.mail.android.mailapp': 'Mail.ru',

    // Банки
    'ru.sberbankmobile': 'СберБанк',
    'com.idamob.tinkoff.android': 'Т-Банк',
    'ru.alfabank.mobile.android': 'Альфа-Банк',
    'ru.vtb24.mobilebanking.android': 'ВТБ',
    'ru.gazprombank.android.mobilebank.app': 'Газпромбанк',
    'ru.raiffeisennews': 'Райффайзен Банк',

    // Маркетплейсы и объявления
    'ru.ozon.app.android': 'Ozon',
    'com.wildberries.ru': 'Wildberries',
    'com.avito.android': 'Авито',

    // Яндекс
    'ru.yandex.taxi': 'Яндекс Go',
    'ru.yandex.market': 'Яндекс Маркет',
    'ru.yandex.music': 'Яндекс Музыка',
    'ru.yandex.maps': 'Яндекс Карты',
    'com.yandex.browser': 'Яндекс Браузер',

    // Кино и доставка
    'ru.kinopoisk': 'Кинопоиск',
    'ru.ivi.client': 'Иви',
    'com.deliveryclub': 'Delivery Club',

    // Операторы связи
    'ru.mts.mymts': 'МТС',
    'ru.megafon.mlk': 'МегаФон',
    'com.beeline.beezone': 'Билайн',
  };

  static Iterable<String> get packages => apps.keys;

  static String nameOf(String package) => apps[package] ?? package;
}
