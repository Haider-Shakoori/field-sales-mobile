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

  // ---------------------------------------------------------------------------
  // Batch 7 — attendance / GPS tracking
  // ---------------------------------------------------------------------------
  String get startDay => _t('Start Day');
  String get endDay => _t('End Day');
  String get endDayConfirmTitle => _t('End your work session?');
  String get endDayConfirmBody =>
      _t('GPS tracking will stop and the session will be completed.');
  String get cancel => _t('Cancel');
  String get working => _t('Working');
  String get trackingActive => _t('Tracking Active');
  String get trackingPaused => _t('Tracking paused');
  String get trackingInactive => _t('Tracking inactive');
  String get dayNotStarted => _t('Day not started');
  String get dayCompleted => _t('Day completed');
  String get startYourDay =>
      _t('Start Day to begin the work session and GPS tracking.');
  String get sessionStartedAt => _t('Started');
  String get elapsedLabel => _t('Elapsed');
  String get gpsStatusLabel => _t('GPS');
  String get waitingForFix => _t('Waiting for GPS fix');
  String lastCapturedAt(String time) => _t('Last: $time');
  String pendingGpsPoints(int n) => _t('$n GPS points pending upload');
  String get gpsAllUploaded => _t('All GPS points uploaded');
  String get attendanceHistory => _t('Attendance history');
  String get attendanceHistoryEmpty => _t('No work sessions recorded yet');
  String get retry => _t('Retry');
  String get resumeTracking => _t('Resume tracking');
  String get openSettings => _t('Open settings');
  String get openLocationSettings => _t('Location settings');
  String get ok => _t('OK');
  String get today => _t('Today');

  String get gpsPrivacyTitle => _t('Location tracking disclosure');
  String get gpsPrivacyIntro => _t(
    'Before you start your first tracked work day, please read and accept:',
  );
  String get gpsPrivacyBullet1 => _t(
    'Location is collected only while a work session is active — from Start Day until End Day.',
  );
  String get gpsPrivacyBullet2 => _t(
    'Tracking continues while the app is in the background or the screen is off.',
  );
  String get gpsPrivacyBullet3 => _t(
    'A persistent "Location tracking active" notification stays visible on Android while tracking runs.',
  );
  String get gpsPrivacyBullet4 =>
      _t('Tracking stops when the work session ends.');
  String get gpsPrivacyBullet5 => _t(
    'GPS records may be retained according to your employer/company policy.',
  );
  String get gpsPrivacyBullet6 => _t(
    'Recorded points are uploaded to your company server when a connection is available.',
  );
  String get gpsPrivacyAgree => _t('I understand and agree');
  String get gpsPrivacyDecline => _t('Not now');

  String get servicesDisabledTitle => _t('Location services are off');
  String get servicesDisabledBody =>
      _t('Turn on device location to start the work day.');
  String get permissionDeniedTitle => _t('Location permission required');
  String get permissionDeniedBody =>
      _t('Field Sales needs foreground location to track the work session.');
  String get permissionPermanentlyDeniedBody => _t(
    'Location permission is blocked. Open app settings and allow location access.',
  );
  String get locationUnavailableTitle => _t('No GPS fix available');
  String get locationUnavailableBody => _t(
    'A location fix is required to start the day. Move to an open area and try again.',
  );
  String get backgroundLocationTitle => _t('Background location not set');
  String get backgroundLocationBody => _t(
    'Tracking works through a visible foreground service. To allow all-the-time access, open settings and choose "Allow all the time".',
  );
  String get trackingStartFailed =>
      _t('The work session was saved, but GPS tracking could not start yet.');
  String get notificationPermissionTitle => _t('Tracking notification hidden');
  String get notificationPermissionBody => _t(
    'Notifications are disabled for Field Sales, so the persistent tracking notification cannot be displayed. Open app settings and allow notifications so tracking stays visible.',
  );
  String get endDayFallbackNote =>
      _t('Ended using the last recorded position instead of a fresh GPS fix.');
  String get noGpsWithoutSession =>
      _t('No active work session — GPS tracking is off.');
  String get authorizationLostTitle => _t('Device access revoked');
  String get authorizationLostBody => _t(
    'Tracking stopped because this device/session is no longer authorized. Unsynced GPS points are preserved. Sign in again or contact your administrator.',
  );
  String get trackingPermissionPaused =>
      _t('Tracking is paused because location permission is missing.');
  String get trackingServicesPaused =>
      _t('Tracking is paused because location services are off.');
  String get syncPending => _t('Pending sync');
  String get syncSynced => _t('Synced');
  String get syncFailed => _t('Sync failed');
  String get statusActive => _t('Active');
  String get statusCompleted => _t('Completed');
  String get durationLabel => _t('Duration');
  String get syncStatusLabel => _t('Sync');
  String get gpsMockSignal => _t(
    'Some points were flagged by the device as mock locations (telemetry only).',
  );

  // ---------------------------------------------------------------------------
  // Company-controlled automatic attendance policy
  // ---------------------------------------------------------------------------
  String get automaticWorkDay => _t('Automatic Work Day');
  String startsAt(String time) => _t('Starts at $time');
  String scheduleWindow(String start, String end) =>
      _t('Scheduled $start – $end');
  String get automaticTrackingWaiting => _t('Automatic tracking waiting');
  String get reviewTrackingPolicy => _t('Review tracking policy');
  String get reviewTrackingPolicyHint => _t(
    'Automatic tracking is configured by your company. Review the tracking policy to begin.',
  );
  String get grantLocationPermission => _t('Grant location permission');
  String get locationPermissionRequired => _t('Location permission required');
  String get locationServicesDisabled => _t('Location services disabled');
  String get automaticWaitingForLocation => _t('Waiting for a GPS location');
  String get timezoneUnavailable =>
      _t('Company timezone unavailable. Contact your administrator.');
  String get gpsDisabledByPolicy =>
      _t('Continuous GPS is disabled by company policy.');
  String get workDayNotActive => _t('Work day not active');
  String get startedAutomatically => _t('Started automatically');
  String get sessionAlreadyCompletedToday =>
      _t('A work session already exists for today.');

  static const List<Locale> supported = supportedLocales;
}
