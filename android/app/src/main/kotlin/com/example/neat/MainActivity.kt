package com.example.neat

import android.content.Intent
import android.net.Uri
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

    // com.instagram.barcelona is NOT a renamed Instagram package — it's
    // Threads' actual package id (confirmed on the Play Store listing).
    // Instagram's package has always been, and still is, com.instagram.android.
    // A previous "fix" here treated barcelona as an Instagram fallback, which
    // is exactly what sent Android users to Threads instead of Instagram DMs.
    private val instagramPackageName = "com.instagram.android"

    // Ground truth, from dumping the real Instagram 438.0 AndroidManifest
    // (not guesswork — the APK's manifest was pulled apart with aapt2):
    //
    //  * The ONLY text/plain ACTION_SEND handler in the entire app is
    //    com.instagram.direct.share.handler.DirectShareHandlerActivity, and
    //    it ships android:enabled=false — Meta flips it on per-device at
    //    runtime via server config. While it's off, NO text share can
    //    resolve, no matter what extras the intent carries. That's why every
    //    previous attempt "always fell back".
    //  * The feed/story/reel handlers are enabled but accept only image/*
    //    and video/*, and they open the feed flow — not DMs.
    //  * instagram://sharesheet IS registered on Android (same route the
    //    working iOS implementation uses), dispatched through
    //    com.instagram.url.UrlHandlerLauncherActivity — the same activity
    //    every instagram:// deep link and instagram.com App Link goes
    //    through, so it's runtime-enabled on any install that has opened
    //    Instagram at least once.
    //
    // Hence the order below: sharesheet deep link first, the gated Direct
    // handler second, an implicit text send third (future-proofing for
    // versions where the gate is open), OS chooser last.
    private fun shareToInstagramDm(text: String) {
        val sharesheet = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("instagram://sharesheet?text=${Uri.encode(text)}"),
        ).apply { setPackage(instagramPackageName) }
        if (tryStart(sharesheet)) return

        val directHandler = Intent(Intent.ACTION_SEND).apply {
            setClassName(instagramPackageName, "com.instagram.direct.share.handler.DirectShareHandlerActivity")
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        if (tryStart(directHandler)) return

        val implicitSend = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            setPackage(instagramPackageName)
        }
        if (tryStart(implicitSend)) return

        val fallback = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(fallback, "Share via"))
    }

    // resolveActivity respects the target component's *runtime* enabled
    // state, so it correctly reports whether Meta's gated components are
    // usable on this particular device right now. The catch covers the
    // remaining races (e.g. Instagram updated between resolve and start).
    private fun tryStart(intent: Intent): Boolean {
        if (intent.resolveActivity(packageManager) == null) return false
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
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
