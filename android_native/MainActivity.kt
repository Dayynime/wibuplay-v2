package com.dayynime.wibuplay

import android.app.DownloadManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.view.accessibility.AccessibilityManager
import java.security.MessageDigest
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

        // Channel "wibuplay/security" (port IntegrityGuard.kt + PremiumStatusCache Zenime).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wibuplay/security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectedTool" -> {
                        val extra = call.argument<List<String>>("extra") ?: emptyList()
                        result.success(try { detectedTool(extra) } catch (e: Exception) { null })
                    }
                    "signatureHashes" -> result.success(try { signatureHashes() } catch (e: Exception) { emptyList<String>() })
                    "hmacSign" -> {
                        val data = call.argument<String>("data") ?: ""
                        result.success(try { hmacSign(data) } catch (e: Exception) { "" })
                    }
                    else -> result.notImplemented()
                }
            }

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

    // ---------------------------------------------------------------- security

    private val toolKeywords = listOf(
        "reqable", "httptoolkit", "httpcanary", "pcapdroid", "remote_capture",
        "sslcapture", "mitm", "charles", "fiddler", "wireshark",
        // Auto clicker. Jangan pakai kata umum ("clicker"/"tap"/"macro").
        "autoclick", "auto click", "autotap", "auto tap", "klik otomatis", "pengklik"
    )

    private val accessibilityWhitelist = setOf(
        "com.google.android.marvin.talkback",
        "com.android.talkback",
        "com.samsung.android.accessibility.talkback",
        "com.google.android.apps.accessibility.voiceaccess"
    )

    /** Nama app terlarang yang terdeteksi, atau null kalau aman. */
    private fun detectedTool(extra: List<String>): String? {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = if (Build.VERSION.SDK_INT >= 33) {
            pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(launcher, 0)
        }
        val keys = (toolKeywords + extra).map { it.lowercase() }
        for (info in apps) {
            val pkg = info.activityInfo.packageName
            if (pkg == packageName) continue
            val label = info.loadLabel(pm).toString()
            val haystack = "$pkg $label".lowercase()
            if (keys.any { it in haystack }) return label
        }
        return detectedGestureService()
    }

    /** Auto clicker butuh Accessibility Service yang boleh dispatch gesture. */
    private fun detectedGestureService(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager ?: return null
        val pm = packageManager
        val services = try {
            am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        } catch (e: Exception) {
            return null
        }
        for (info in services) {
            val serviceInfo = info.resolveInfo?.serviceInfo ?: continue
            val pkg = serviceInfo.packageName
            if (pkg == packageName || pkg in accessibilityWhitelist) continue
            val appFlags = serviceInfo.applicationInfo?.flags ?: 0
            val isSystem = appFlags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            if (isSystem) continue
            val canGesture = info.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_PERFORM_GESTURES != 0
            if (canGesture) {
                return serviceInfo.applicationInfo?.loadLabel(pm)?.toString() ?: pkg
            }
        }
        return null
    }

    /** SHA-256 (hex kecil) semua sertifikat penandatangan APK ini. */
    @Suppress("DEPRECATION")
    private fun signatureHashes(): List<String> {
        val pm = packageManager
        val certs = if (Build.VERSION.SDK_INT >= 28) {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val si = info.signingInfo ?: return emptyList()
            if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
        } else {
            pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
        }
        if (certs == null) return emptyList()
        val md = MessageDigest.getInstance("SHA-256")
        return certs.map { sig -> md.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) } }
    }

    /** HMAC-SHA256 pakai key AndroidKeyStore (tidak bisa diekspor dari device). */
    private fun hmacSign(data: String): String {
        val alias = "wibuplay_premium_cache_hmac"
        val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        var key = ks.getKey(alias, null) as? javax.crypto.SecretKey
        if (key == null) {
            val gen = javax.crypto.KeyGenerator.getInstance(
                android.security.keystore.KeyProperties.KEY_ALGORITHM_HMAC_SHA256,
                "AndroidKeyStore"
            )
            gen.init(
                android.security.keystore.KeyGenParameterSpec.Builder(
                    alias,
                    android.security.keystore.KeyProperties.PURPOSE_SIGN
                ).build()
            )
            key = gen.generateKey()
        }
        val mac = javax.crypto.Mac.getInstance("HmacSHA256")
        mac.init(key)
        return mac.doFinal(data.toByteArray()).joinToString("") { "%02x".format(it) }
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
