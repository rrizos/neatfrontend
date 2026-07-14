package com.example.neat

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
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
                        val imageBytes = call.argument<ByteArray>("imageBytes")
                        shareToInstagramDm(text, imageBytes)
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

    private fun isInstagramInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo(instagramPackageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    // Instagram doesn't publicly document a "share straight to Direct" intent,
    // but com.instagram.direct.share.handler.DirectShareHandlerActivity is the
    // internal activity apps like Spotify rely on to do exactly that — it
    // accepts plain EXTRA_TEXT directly into Direct's compose screen, no
    // attached image required. It's an undocumented, version-fragile internal
    // class name (this is literally the kind of detail Meta has renamed
    // before), so every call is wrapped and falls through to the next
    // strategy rather than crashing if a future Instagram update removes it.
    private fun tryInstagramDirectHandler(text: String, imageUri: Uri?): Boolean {
        val intent = Intent(Intent.ACTION_SEND).apply {
            setClassName(instagramPackageName, "com.instagram.direct.share.handler.DirectShareHandlerActivity")
            if (imageUri != null) {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, imageUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                type = "text/plain"
            }
            putExtra(Intent.EXTRA_TEXT, text)
        }
        return try {
            if (intent.resolveActivity(packageManager) == null) return false
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun writeShareImageUri(imageBytes: ByteArray?): Uri? {
        if (imageBytes == null || imageBytes.isEmpty()) return null
        return try {
            val file = File(cacheDir, "neat_share_ig.jpg")
            FileOutputStream(file).use { it.write(imageBytes) }
            FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        } catch (_: Exception) {
            null
        }
    }

    // Instagram's Android app doesn't declare a *public* handler for bare
    // text/plain ACTION_SEND intents — it only reliably resolves ACTION_SEND
    // with an attached image (image/*), which opens Instagram's own
    // share-destination picker (Direct included). iOS doesn't have this
    // limitation because it uses Instagram's own instagram://sharesheet URL
    // scheme, which does accept text.
    private fun shareToInstagramDm(text: String, imageBytes: ByteArray?) {
        val imageUri = writeShareImageUri(imageBytes)

        // 1) Internal Direct-compose activity — works with or without an
        // image, and is the closest match to a real "share to Instagram DM".
        if (tryInstagramDirectHandler(text, imageUri)) return

        // 2) Public image share into Instagram's own picker (Direct is one of
        // the destinations offered there) — reliable whenever there's an image.
        if (imageUri != null) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, imageUri)
                putExtra(Intent.EXTRA_TEXT, text)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                setPackage(instagramPackageName)
            }
            if (intent.resolveActivity(packageManager) != null) {
                try {
                    startActivity(intent)
                    return
                } catch (_: ActivityNotFoundException) {
                    // Fall through below.
                }
            }
        }

        // 3) No image (or nothing above resolved) — best-effort text-only
        // attempts, most likely to end at the generic chooser since Instagram
        // doesn't reliably accept plain text via public intents on Android.
        val deepLink = Intent(Intent.ACTION_VIEW, Uri.parse("instagram://sharesheet?text=${Uri.encode(text)}")).apply {
            setPackage(instagramPackageName)
        }
        if (deepLink.resolveActivity(packageManager) != null) {
            try {
                startActivity(deepLink)
                return
            } catch (_: ActivityNotFoundException) {
                // Fall through below.
            }
        }
        if (isInstagramInstalled()) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                setPackage(instagramPackageName)
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
