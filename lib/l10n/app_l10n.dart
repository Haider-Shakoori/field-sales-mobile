import 'package:flutter/material.dart';

/// Locales the app is prepared for (English / Dari / Pashto).
const supportedLocales = [
  Locale('en'),
  Locale('fa'), // Dari (transliteration target)
  Locale('ps'), // Pashto
];

/// Inline localization foundation for Batch 6.
///
/// Uses a lightweight key lookup rather than the full gen-l10n pipeline —
/// enough to establish the English/Dari/Pashto structure the roadmap calls
/// for, and swappable for `l10n.yaml` codegen in a later batch.
class AppL10n {
  AppL10n({required this.locale});

  factory AppL10n.of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return AppL10n(locale: locale);
  }

  final Locale locale;

  bool get _isFa => locale.languageCode == 'fa';
  bool get _isPs => locale.languageCode == 'ps';

  String _t(String en, [String? fa, String? ps]) {
    if (_isFa && fa != null) {
      return fa;
    }
    if (_isPs && ps != null) {
      return ps;
    }
    return en;
  }

  String get appTitle => _t('Field Sales', 'فروش میدانی', 'د ساحې پلور');

  String get signIn => _t('Sign in', 'ورود', 'ننوتل');
  String get email => _t('Email', 'ایمیل', 'بریښنالیک');
  String get password => _t('Password', 'رمز عبور', 'پاسورډ');
  String get signInButton => _t('Sign in', 'ورود', 'ننوتل');
  String get signingIn => _t('Signing in…', 'در حال ورود…', 'ننوتل روان…');
  String get invalidCredentials => _t(
    'Invalid email or password.',
    'ایمیل یا رمز عبور نادرست است.',
    'ناسم بریښنالیک یا پاسورډ.',
  );
  String get accountDeactivated => _t(
    'This account has been deactivated.',
    'این حساب غیرفعال شده است.',
    'دا حساب غیر فعال شوی.',
  );
  String get deviceRevoked => _t(
    'This device was revoked. Contact your administrator.',
    'این دستگاه لغو شده. با مدیر خود تماس بگیرید.',
    'دا وسیله لغوه شوې. له مدیر سره اړیکه ونیسئ.',
  );
  String get networkError => _t(
    'Network error. Check your connection.',
    'خطای شبکه. اتصال خود را بررسی کنید.',
    'د شبکې تېروتنه.',
  );
  String get unexpectedError => _t(
    'Something went wrong.',
    'خطای غیرمنتظره.',
    'یوه تېروتنه رامنځته شوه.',
  );

  String get dashboard => _t('Dashboard', 'داشبورد', 'ډشبورډ');
  String get routes => _t('Routes', 'مسیرها', 'لارې');
  String get customers => _t('Customers', 'مشتریان', 'پیرودونکي');
  String get products => _t('Products', 'محصولات', 'محصولات');
  String get priceListsLabel => _t('Price lists', 'قیمتها', 'نرخنامه');
  String get profile => _t('Profile', 'پروفایل', 'پېژندلړ');

  String get online => _t('Online', 'آنلاین', 'آنلاین');
  String get offline => _t('Offline', 'آفلاین', 'آفلاین');
  String get limited => _t('Limited', 'محدود', 'محدود');
  String get syncing => _t('Syncing…', 'در حال همگامسازی…', 'همغږي کول روان…');
  String pending(int n) => _t('$n pending', '$n در انتظار', '$n په تماس');
  String failed(int n) => _t('$n failed', '$n ناموفق', '$n ناکام');

  String get welcome => _t('Welcome', 'خوش آمدید', 'ښه راغلاست');
  String get signOut => _t('Sign out', 'خروج', 'وتل');
  String get refresh => _t('Refresh', 'تازه کردن', 'تازه کول');
  String get lastUpdated =>
      _t('Last updated', 'آخرین بهروزرسانی', 'وروستی تازه کول');
  String get updateRequiredMessage => _t(
    'A new version of the app is required. Please update from the store.',
    'نسخه جدیدی از برنامه نیاز است. لطفاً از فروشگاه بهروزرسانی کنید.',
    'د اپلیکیشن نوې نسخه اړینه ده. مهرباني وکړئ له پلورنځي تازه یې کړئ.',
  );
  String get noData =>
      _t('No data yet', 'هنوز دادهای نیست', 'لا تر اوسه معلومات نشته');
  String get pullToRefresh =>
      _t('Pull to refresh', 'بکشید تا تازه شود', 'د تازه کولو لپاره راکش کړئ');
  String get error =>
      _t('Something went wrong', 'خطایی رخ داد', 'یوه تېروتنه رامنځته شوه');
  String itemsCount(int n) => _t('$n items', '$n مورد', '$n توکي');
  String customersCount(int n) =>
      _t('$n customers', '$n مشتری', '$n پیرودونکي');
  String routesCount(int n) => _t('$n routes', '$n مسیر', '$n لارې');

  static const List<Locale> supported = supportedLocales;
}
