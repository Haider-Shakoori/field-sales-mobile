import 'package:flutter/services.dart';

/// Notifications permission needed for the Android foreground-service
/// notification to be visible in the shade (Android 13+ / POST_NOTIFICATIONS).
///
/// geolocator cannot request this permission, so a tiny native bridge in
/// `MainActivity.kt` handles it. Non-Android platforms and tests report
/// granted so tracking is never blocked by a missing platform channel.
abstract class NotificationPermissionService {
  Future<bool> isGranted();

  Future<bool> request();
}

class MethodChannelNotificationPermissionService
    implements NotificationPermissionService {
  MethodChannelNotificationPermissionService({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.fieldsales.field_sales_mobile/permissions');

  final MethodChannel _channel;

  @override
  Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>('hasNotificationPermission') ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }
}
