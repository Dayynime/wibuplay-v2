package com.dayynime.wibuplay

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Intent
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * Channel push "Teman & Clan" (id dipakai Edge Function zenime-notify:
     * android.notification.channel_id = "zenime_social"). IMPORTANCE_HIGH
     * supaya muncul pop-up (heads-up), bukan cuma ikon di status bar.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val nm = getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel("zenime_social") != null) return
            val ch = NotificationChannel(
                "zenime_social",
                "Teman & Clan",
                NotificationManager.IMPORTANCE_HIGH,
            )
            ch.description = "Permintaan pertemanan dan request join clan"
            nm.createNotificationChannel(ch)
        } catch (e: Exception) {
            // Gagal bikin channel tidak boleh bikin app crash.
        }
    }

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
        "netcapture", "packet capture", "packetcapture", "proxyman",
        "netbare", "proxymon"
    )

    /** Paket app capture/MITM yang dikenal (dicocokkan persis). */
    private val toolPackages = setOf(
        "com.guoshi.httpcanary", "com.guoshi.httpcanary.premium",
        "app.greyshirts.sslcapture",
        "com.emanuelef.remote_capture",
        "com.reqable.android",
        "tech.httptoolkit.android.v1",
        "com.minhui.networkcapture", "com.minhui.networkcapture.pro",
        "jp.co.taosoftware.android.packetcapture",
        "com.evbadroid.proxymon",
        "com.github.megatronking.netbare.sample",
        "com.packagesniffer.frtparlak"
    )

    /**
     * Sertifikat CA yang dipasang USER (Setelan > Keamanan > Kredensial pengguna).
     * App capture/MITM memasang sertifikat seperti ini untuk membaca HTTPS.
     * Mengembalikan nama sertifikat pertama, atau null kalau tidak ada.
     */
    private fun userCaName(): String? {
        return try {
            val ks = KeyStore.getInstance("AndroidCAStore")
            ks.load(null, null)
            val aliases = ks.aliases()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                if (!alias.startsWith("user:")) continue
                val cert = ks.getCertificate(alias) as? X509Certificate
                val dn = cert?.subjectX500Principal?.name ?: ""
                val cn = Regex("CN=([^,]+)").find(dn)?.groupValues?.get(1)
                    ?: Regex("O=([^,]+)").find(dn)?.groupValues?.get(1)
                return cn?.trim()?.takeIf { it.isNotEmpty() } ?: "tidak dikenal"
            }
            null
        } catch (e: Exception) {
            null
        }
    }

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
            if (pkg in toolPackages) return label
            val haystack = "$pkg $label".lowercase()
            if (keys.any { it in haystack }) return label
        }
        userCaName()?.let { return "Sertifikat CA pengguna: $it" }
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
