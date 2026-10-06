package com.dayynime.wibuplay

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity Wibuplay + Picture-in-Picture (port PipController.kt Zenime).
 * Disalin ke android/app/src/main/kotlin/... oleh CI (menimpa bawaan flutter create).
 *
 * Channel "wibuplay/pip":
 *  - setCanEnter(bool)         : player aktif & sedang memutar -> auto-PiP saat user pindah app
 *  - setAspectRatio({w,h})     : rasio video untuk jendela PiP
 *  - enter({force})            : masuk PiP (tombol manual pakai force=true), return bool
 *  - onPipChanged(bool)        : native -> Dart, status mode PiP
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
