package com.cura.cura

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// local_auth needs FlutterFragmentActivity — its prompt no-ops under FlutterActivity.
class MainActivity : FlutterFragmentActivity() {
    // Real hardware readout for the onboarding engine recommendation. RAM comes
    // from ActivityManager.totalMem, since the Vulkan probe only sees the
    // GPU-visible heap, far below physical RAM on unified-memory SoCs.
    private val channel = "com.cura.cura/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PdfDownloadsSaver(this).register(flutterEngine)
        PdfPageRenderer(this).register(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInfo" -> result.success(deviceInfo())
                    // Read from the installed package so the Settings row can
                    // never drift from the version in pubspec.
                    "getVersion" ->
                        result.success(
                            packageManager.getPackageInfo(packageName, 0).versionName
                        )
                    // The only way back once notifications are permanently
                    // denied, since the OS stops showing the prompt.
                    "openNotificationSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        )
                        result.success(null)
                    }
                    // Updates: unknown-apps prompt; same signing key only.
                    "canInstallPackages" ->
                        result.success(packageManager.canRequestPackageInstalls())
                    "openInstallPermission" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                        )
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null || !File(path).exists()) {
                            result.error("missing", "Update file not found", null)
                        } else {
                            installApk(File(path))
                            result.success(null)
                        }
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null || !url.startsWith("https://")) {
                            result.error("bad_url", "Only https links open", null)
                        } else {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Installer reads the APK via FileProvider (updates/ only).
    private fun installApk(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                )
        )
    }

    private fun deviceInfo(): Map<String, Any?> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mem)

        val socManufacturer =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MANUFACTURER else ""
        val socModel =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else ""

        // advertisedMem (API 34+) is the retail figure, including memory the
        // kernel can't see, so totalMem always reads a few hundred MB lower.
        // 0 signals unavailable and Dart falls back to totalMem.
        val advertisedRam =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mem.advertisedMem
            } else {
                0L
            }

        return mapOf(
            "advertisedRamBytes" to advertisedRam,
            // totalMem ≈ advertised RAM (a little lower, minus reserved memory).
            "totalRamBytes" to mem.totalMem,
            "availRamBytes" to mem.availMem,
            "cores" to Runtime.getRuntime().availableProcessors(),
            "socManufacturer" to socManufacturer,
            "socModel" to socModel,
            "hardware" to (Build.HARDWARE ?: ""),
            "board" to (Build.BOARD ?: ""),
            "cpuHardwareLine" to cpuHardwareLine(),
        )
    }

    // Best-effort "Hardware :" line from /proc/cpuinfo, populated on many
    // Qualcomm/MediaTek chips and usually empty on Exynos. Never throws.
    private fun cpuHardwareLine(): String {
        return try {
            File("/proc/cpuinfo").useLines { lines ->
                lines.firstOrNull { it.startsWith("Hardware", ignoreCase = true) }
                    ?.substringAfter(':', "")
                    ?.trim()
                    ?: ""
            }
        } catch (_: Exception) {
            ""
        }
    }
}
