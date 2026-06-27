package com.example.neat

import android.content.Intent
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
                if (call.method == "share") {
                    val text = call.argument<String>("text") ?: ""
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    nativeShare(text, imageBytes)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
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
