package com.wesoft.fieldsales
import android.Manifest
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
class MainActivity: FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) { super.configureFlutterEngine(flutterEngine); MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"field_sales/notifications").setMethodCallHandler { call,result -> if(call.method=="requestNotificationPermission"){ if(Build.VERSION.SDK_INT>=33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),9101); result.success(true) } else result.notImplemented() } }
}
