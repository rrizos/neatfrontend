package com.example.neat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val SHARE_CHANNEL = "com.neat/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "share" -> {
                        val text = call.argument<String>("text") ?: ""
                        val imageBytes = call.argument<ByteArray>("imageBytes")
                        nativeShare(text, imageBytes)
                        result.success(null)
                    }
                    "shareToInstagramDm" -> {
                        val text = call.argument<String>("text") ?: ""
                        shareToInstagramDm(text)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Meta renamed Instagram's Android package at some point from
    // com.instagram.android to com.instagram.barcelona (confirmed via
    // `adb shell pm list packages` on a real current-Instagram device) —
    // the old package name doesn't exist any more on updated installs, so
    // targeting it always threw ActivityNotFoundException and silently fell
    // back to the generic chooser. Try both, in case some installs still use
    // the old name.
    private val instagramPackageCandidates = listOf("com.instagram.android", "com.instagram.barcelona")

    private fun installedInstagramPackage(): String? {
        for (pkg in instagramPackageCandidates) {
            try {
                packageManager.getPackageInfo(pkg, 0)
                return pkg
            } catch (_: PackageManager.NameNotFoundException) {}
        }
        return null
    }

    private fun shareToInstagramDm(text: String) {
        val igPackage = installedInstagramPackage()
        if (igPackage != null) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                setPackage(igPackage)
            }
            try {
                startActivity(intent)
                return
            } catch (_: ActivityNotFoundException) {
                // Fall through to the generic chooser below.
            }
        }
        val fallback = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(fallback, "Share via"))
    }

    private fun nativeShare(text: String, imageBytes: ByteArray?) {
        val intent = Intent(Intent.ACTION_SEND)

        if (imageBytes != null && imageBytes.isNotEmpty()) {
            try {
                val file = File(cacheDir, "neat_share.jpg")
                FileOutputStream(file).use { it.write(imageBytes) }
                val uri = FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    file
                )
                intent.type = "image/jpeg"
                intent.putExtra(Intent.EXTRA_STREAM, uri)
                intent.putExtra(Intent.EXTRA_TEXT, text)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) {
                // Fall back to text-only if image writing fails
                intent.type = "text/plain"
                intent.putExtra(Intent.EXTRA_TEXT, text)
            }
        } else {
            intent.type = "text/plain"
            intent.putExtra(Intent.EXTRA_TEXT, text)
        }

        startActivity(Intent.createChooser(intent, "Share via"))
    }
}
