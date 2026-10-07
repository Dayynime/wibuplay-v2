package com.dayynime.wibuplay

import android.app.DownloadManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MainActivity Wibuplay + Picture-in-Picture (port PipController.kt Zenime).
 * Disalin ke android/app/src/main/kotlin/... oleh CI (menimpa bawaan flutter create).
 *
 * Channel "wibuplay/pip":
 *  - setCanEnter(bool)         : player aktif & sedang memutar -> auto-PiP saat user pindah app
 *  - setAspectRatio({w,h})     : rasio video untuk jendela PiP
 *  - enter({force})            : masuk PiP (tombol manual pakai force=true), return bool
 *  - onPipChanged(bool)        : native -> Dart, status mode PiP
 *
 * Channel "wibuplay/download" (port EpisodeDownloadManager.kt Zenime): download
 * episode lewat android.app.DownloadManager sistem, jadi tetap jalan walau app
 * di-swipe dan ada notifikasi bawaan.
 *  - enqueue({url,path,title,description,headers}) : id download (Long)
 *  - query({id})   : {status(int), bytes, total} atau null kalau id tidak ada
 *  - remove({id})  : batalkan + hapus
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var canEnter = false
    private var ratio = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wibuplay/pip")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCanEnter" -> {
                    canEnter = (call.arguments as? Boolean) ?: false
                    result.success(null)
                }
                "setAspectRatio" -> {
                    val w = call.argument<Int>("w") ?: 0
                    val h = call.argument<Int>("h") ?: 0
                    if (w > 0 && h > 0) {
                        // PiP hanya menerima rasio antara 1:2.39 dan 2.39:1.
                        val r = w.toFloat() / h.toFloat()
                        if (r >= 1f / 2.39f && r <= 2.39f) ratio = Rational(w, h)
                    }
                    result.success(null)
                }
                "enter" -> {
                    val force = call.argument<Boolean>("force") ?: false
                    result.success(enterPip(force))
                }
                else -> result.notImplemented()
            }
        }
        channel = ch

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wibuplay/download")
            .setMethodCallHandler { call, result ->
                val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                when (call.method) {
                    "enqueue" -> {
                        try {
                            val url = call.argument<String>("url") ?: ""
                            val path = call.argument<String>("path") ?: ""
                            val req = DownloadManager.Request(Uri.parse(url))
                                .setTitle(call.argument<String>("title") ?: "Download")
                                .setDescription(call.argument<String>("description") ?: "")
                                .setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                                )
                                .setDestinationUri(Uri.fromFile(File(path)))
                                .setAllowedOverMetered(true)
                                .setAllowedOverRoaming(true)
                            val headers = call.argument<Map<String, String>>("headers")
                            headers?.forEach { (k, v) -> req.addRequestHeader(k, v) }
                            result.success(dm.enqueue(req))
                        } catch (e: Exception) {
                            result.error("ENQUEUE", e.message, null)
                        }
                    }
                    "query" -> {
                        try {
                            val id = (call.argument<Number>("id"))?.toLong() ?: -1L
                            val cursor = dm.query(DownloadManager.Query().setFilterById(id))
                            if (cursor == null) {
                                result.success(null)
                            } else {
                                cursor.use { c ->
                                    if (!c.moveToFirst()) {
                                        result.success(null)
                                    } else {
                                        result.success(
                                            mapOf(
                                                "status" to c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)),
                                                "bytes" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                                                "total" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                                            )
                                        )
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            result.error("QUERY", e.message, null)
                        }
                    }
                    "remove" -> {
                        try {
                            val id = (call.argument<Number>("id"))?.toLong() ?: -1L
                            result.success(dm.remove(id))
                        } catch (e: Exception) {
                            result.success(0)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enterPip(force: Boolean): Boolean {
        if (!force && !canEnter) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        val params = PictureInPictureParams.Builder().setAspectRatio(ratio).build()
        return try {
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        enterPip(false)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
