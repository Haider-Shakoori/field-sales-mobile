package com.businessos.fieldpulse

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val notificationChannel = "field_sales/notifications"
        private const val operationalNotificationChannelId = "fieldpulse_operational"
        private const val audioChannel = "field_sales/voice_recorder"
        private const val diagnosticsChannel = "field_sales/device_diagnostics"
        private const val notificationPermissionRequestCode = 9101
        private const val audioPermissionRequestCode = 9102
    }

    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingAudioPermissionResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var recordingStartedAtMs: Long? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOperationalNotificationChannel()
    }

    private fun createOperationalNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            operationalNotificationChannelId,
            "FieldPulse alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Operational alerts, supervisor messages, and sales updates."
            enableVibration(true)
        }

        manager.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestNotificationPermission") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                result.success(true)
                return@setMethodCallHandler
            }

            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
                return@setMethodCallHandler
            }

            if (pendingNotificationPermissionResult != null) {
                result.error(
                    "PERMISSION_REQUEST_IN_PROGRESS",
                    "Notification permission is already being requested.",
                    null,
                )
                return@setMethodCallHandler
            }

            pendingNotificationPermissionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            audioChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestAudioPermission(result)
                "start" -> startRecording(result)
                "stop" -> stopRecording(result)
                "cancel" -> cancelRecording(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            diagnosticsChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "snapshot") {
                result.success(deviceDiagnosticSnapshot())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun deviceDiagnosticSnapshot(): Map<String, Any?> {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val statFs = StatFs(filesDir.absolutePath)

        val fineLocationGranted =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val coarseLocationGranted =
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val backgroundLocationGranted =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
            } else {
                fineLocationGranted || coarseLocationGranted
            }
        val notificationGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

        val locationServicesEnabled = try {
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        } catch (_: Exception) {
            false
        }

        val blockSize = statFs.blockSizeLong
        val availableBytes = statFs.availableBlocksLong * blockSize
        val totalBytes = statFs.blockCountLong * blockSize
        val bytesPerMb = 1024L * 1024L

        return mapOf(
            "power_save_mode" to powerManager.isPowerSaveMode,
            "battery_optimization_exempt" to
                powerManager.isIgnoringBatteryOptimizations(packageName),
            "background_restricted" to
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    activityManager.isBackgroundRestricted
                } else {
                    false
                },
            "location_services_enabled" to locationServicesEnabled,
            "location_permission" to when {
                fineLocationGranted -> "granted"
                coarseLocationGranted -> "coarse"
                else -> "denied"
            },
            "background_location_permission" to
                if (backgroundLocationGranted) "granted" else "denied",
            "notification_permission" to
                if (notificationGranted) "granted" else "denied",
            "storage_free_mb" to availableBytes / bytesPerMb,
            "storage_total_mb" to totalBytes / bytesPerMb,
            "root_signal_detected" to hasRootSignal(),
        )
    }

    private fun hasRootSignal(): Boolean {
        if (Build.TAGS?.contains("test-keys") == true) {
            return true
        }

        return listOf(
            "/system/app/Superuser.apk",
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/su/bin/su",
        ).any { path -> File(path).exists() }
    }

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        if (pendingAudioPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "Microphone permission is already being requested.",
                null,
            )
            return
        }

        pendingAudioPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            audioPermissionRequestCode,
        )
    }

    private fun startRecording(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error("MIC_PERMISSION_REQUIRED", "Microphone permission is required.", null)
            return
        }

        if (recorder != null) {
            result.error("RECORDING_IN_PROGRESS", "A voice note is already being recorded.", null)
            return
        }

        try {
            val folder = File(filesDir, "visit_voice_notes")
            folder.mkdirs()
            val file = File(
                folder,
                "visit-note-" + System.currentTimeMillis().toString() + ".m4a",
            )
            val nextRecorder = createRecorder()

            nextRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            nextRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            nextRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            nextRecorder.setAudioEncodingBitRate(64000)
            nextRecorder.setAudioSamplingRate(44100)
            nextRecorder.setOutputFile(file.absolutePath)
            nextRecorder.prepare()
            nextRecorder.start()

            recorder = nextRecorder
            recordingFile = file
            recordingStartedAtMs = System.currentTimeMillis()
            result.success(file.absolutePath)
        } catch (error: Exception) {
            releaseRecorder(deleteFile = true)
            result.error("VOICE_RECORDING_START_FAILED", error.message, null)
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        val activeRecorder = recorder
        val file = recordingFile
        val startedAt = recordingStartedAtMs

        if (activeRecorder == null || file == null || startedAt == null) {
            result.error("NO_RECORDING", "No voice note recording is active.", null)
            return
        }

        try {
            activeRecorder.stop()
            val durationSeconds =
                ((System.currentTimeMillis() - startedAt) / 1000L).coerceAtLeast(1L)
            activeRecorder.reset()
            activeRecorder.release()
            recorder = null
            recordingFile = null
            recordingStartedAtMs = null

            result.success(
                mapOf(
                    "path" to file.absolutePath,
                    "duration_seconds" to durationSeconds,
                ),
            )
        } catch (error: Exception) {
            releaseRecorder(deleteFile = true)
            result.error("VOICE_RECORDING_STOP_FAILED", error.message, null)
        }
    }

    private fun cancelRecording(result: MethodChannel.Result) {
        releaseRecorder(deleteFile = true)
        result.success(true)
    }

    @Suppress("DEPRECATION")
    private fun createRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            MediaRecorder()
        }

    private fun releaseRecorder(deleteFile: Boolean) {
        try {
            recorder?.reset()
        } catch (_: Exception) {
        }

        try {
            recorder?.release()
        } catch (_: Exception) {
        }

        recorder = null

        if (deleteFile) {
            recordingFile?.delete()
        }

        recordingFile = null
        recordingStartedAtMs = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED

        when (requestCode) {
            notificationPermissionRequestCode -> {
                pendingNotificationPermissionResult?.success(granted)
                pendingNotificationPermissionResult = null
            }

            audioPermissionRequestCode -> {
                pendingAudioPermissionResult?.success(granted)
                pendingAudioPermissionResult = null
            }
        }
    }

    override fun onDestroy() {
        releaseRecorder(deleteFile = true)
        super.onDestroy()
    }
}
