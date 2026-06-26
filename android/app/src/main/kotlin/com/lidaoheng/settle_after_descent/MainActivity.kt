package com.lidaoheng.settle_after_descent

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var pendingPickImageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "settle_after_descent/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> pickImage(result)
                    "shareFile" -> shareFile(
                        call.argument("path"),
                        call.argument("title"),
                        call.argument("mimeType"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickImage(result: MethodChannel.Result) {
        pendingPickImageResult?.success(null)
        pendingPickImageResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        startActivityForResult(intent, PICK_IMAGE_REQUEST)
    }

    private fun shareFile(path: String?, title: String?, mimeType: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("missing_path", "Share file path is missing", null)
            return
        }
        val source = File(path)
        val shared = File(cacheDir, source.name)
        source.copyTo(shared, overwrite = true)
        val uri = Uri.parse("content://${applicationContext.packageName}.fileprovider/${shared.name}")
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType ?: "application/octet-stream"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title ?: "导出 CSV")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, title ?: "导出 CSV"))
        result.success(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_IMAGE_REQUEST) return
        val result = pendingPickImageResult
        pendingPickImageResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result?.success(null)
            return
        }
        try {
            val backgroundsDir = File(filesDir, "backgrounds").apply { mkdirs() }
            val target = File(backgroundsDir, "trip_bg_${System.currentTimeMillis()}.jpg")
            contentResolver.openInputStream(uri).use { input ->
                FileOutputStream(target).use { output ->
                    input?.copyTo(output)
                }
            }
            result?.success(target.absolutePath)
        } catch (error: Exception) {
            result?.error("pick_failed", error.message, null)
        }
    }

    companion object {
        private const val PICK_IMAGE_REQUEST = 7601
    }
}
