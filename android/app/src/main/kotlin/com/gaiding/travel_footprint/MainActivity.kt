package com.gaiding.travel_footprint

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.gaiding.travel_footprint/media"
    private var lastUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "travel-footprint.png"
                        if (bytes == null) {
                            result.error("no_bytes", "图片数据为空", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val uri = saveToGallery(bytes, name)
                                lastUri = uri
                                runOnUiThread { result.success(uri) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("save_failed", error.message, null) }
                            }
                        }.start()
                    }

                    "shareImage" -> {
                        val uri = call.argument<String>("uri") ?: lastUri
                        if (uri == null) {
                            result.error("no_image", "还没有可分享的图片", null)
                        } else {
                            shareUri(uri)
                            result.success(null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToGallery(bytes: ByteArray, name: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/TravelFootprint"
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val item = resolver.insert(collection, values)
                ?: throw IllegalStateException("无法写入系统相册")
            val stream = resolver.openOutputStream(item)
                ?: throw IllegalStateException("无法打开相册文件")
            stream.use { it.write(bytes) }
            val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            resolver.update(item, done, null, null)
            return item.toString()
        }

        val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
        val dir = File(pictures, "TravelFootprint")
        if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("无法创建保存目录")
        val file = File(dir, name)
        FileOutputStream(file).use { it.write(bytes) }
        return Uri.fromFile(file).toString()
    }

    private fun shareUri(uri: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "分享我的足迹"))
    }
}
