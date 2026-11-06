package com.dayynime.wibuplay

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Pemutar ExoPlayer (Media3) untuk lib/core/wp_video.dart.
 * Disalin ke android/app/src/main/kotlin/... oleh CI, didaftarkan di MainActivity.
 *
 * Channel "wibuplay/exo":
 *  - create({url, headers, startMs, software}) -> {id, textureId}
 *      software=true: decoder software didahulukan (HP yang decoder hardware-nya rusak)
 *  - play/pause/dispose({id}), seek({id, ms}), speed({id, v}), volume({id, v 0..1})
 *
 * Event per pemutar di EventChannel "wibuplay/exo/events/<id>" (Map, kunci "e"):
 *  ready{w,h,d} · size{w,h} · buffering{v} · playing{v} · ended · frame · pos{p,d} · error{msg,code}
 */
@OptIn(markerClass = [UnstableApi::class])
class WpExo(
    private val context: Context,
    private val messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) {
    private val players = HashMap<Long, Item>()
    private var nextId = 1L
    private val channel = MethodChannel(messenger, "wibuplay/exo")

    /** Decoder software didahulukan, hardware tetap jadi cadangan. */
    private val softwareFirst = MediaCodecSelector { mime, secure, tunneling ->
        MediaCodecUtil.getDecoderInfos(mime, secure, tunneling).sortedBy { if (it.softwareOnly) 0 else 1 }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("EXO", e.message ?: e.toString(), null)
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "create") {
            result.success(create(call))
            return
        }
        val id = (call.argument<Number>("id"))?.toLong() ?: -1L
        val item = players[id]
        if (item == null) {
            result.success(null)
            return
        }
        val p = item.player
        when (call.method) {
            "play" -> p.play()
            "pause" -> p.pause()
            "seek" -> p.seekTo(((call.argument<Number>("ms"))?.toLong() ?: 0L).coerceAtLeast(0L))
            "speed" -> {
                val v = ((call.argument<Number>("v"))?.toFloat() ?: 1f).coerceIn(0.25f, 4f)
                p.playbackParameters = PlaybackParameters(v)
            }
            "volume" -> p.volume = ((call.argument<Number>("v"))?.toFloat() ?: 1f).coerceIn(0f, 1f)
            "dispose" -> {
                players.remove(id)
                item.release()
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    private fun create(call: MethodCall): Map<String, Any> {
        val url = call.argument<String>("url") ?: throw IllegalArgumentException("url kosong")
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        val startMs = ((call.argument<Number>("startMs"))?.toLong() ?: 0L).coerceAtLeast(0L)
        val software = call.argument<Boolean>("software") ?: false

        // Kalau decoder pertama gagal dibuka, ExoPlayer otomatis coba decoder lain.
        val renderers = DefaultRenderersFactory(context).setEnableDecoderFallback(true)
        if (software) renderers.setMediaCodecSelector(softwareFirst)

        val http = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)
        if (headers.isNotEmpty()) http.setDefaultRequestProperties(headers)
        val sources = DefaultMediaSourceFactory(context)
            .setDataSourceFactory(DefaultDataSource.Factory(context, http))

        val player = ExoPlayer.Builder(context, renderers)
            .setMediaSourceFactory(sources)
            .build()
        // handleAudioFocus=false: sama dengan media_kit sebelumnya, jadi suara
        // voice Nobar / app lain tidak membuat video berhenti sendiri.
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            false,
        )

        val media = MediaItem.Builder().setUri(url)
        if (url.contains(".m3u8", ignoreCase = true)) media.setMimeType(MimeTypes.APPLICATION_M3U8)

        val id = nextId++
        val producer = textures.createSurfaceProducer()
        val item = Item(id, producer, player)
        players[id] = item

        player.addListener(item)
        player.playWhenReady = false
        player.setMediaItem(media.build(), startMs)
        player.prepare()
        item.start()

        return mapOf("id" to id, "textureId" to producer.id())
    }

    /** Lepas semua pemutar (engine Flutter dihancurkan). */
    fun disposeAll() {
        channel.setMethodCallHandler(null)
        for (item in players.values) item.release()
        players.clear()
    }

    private inner class Item(
        val id: Long,
        val producer: TextureRegistry.SurfaceProducer,
        val player: ExoPlayer,
    ) : Player.Listener, TextureRegistry.SurfaceProducer.Callback {
        private val events = EventChannel(messenger, "wibuplay/exo/events/$id")
        private val handler = Handler(Looper.getMainLooper())
        private var sink: EventChannel.EventSink? = null
        private val queue = ArrayList<Map<String, Any?>>()
        private var released = false
        private var readySent = false
        private var needsSurface = true

        private val ticker = object : Runnable {
            override fun run() {
                if (released) return
                val d = player.duration
                send(mapOf("e" to "pos", "p" to player.currentPosition, "d" to (if (d == C.TIME_UNSET) 0L else d)))
                handler.postDelayed(this, 200)
            }
        }

        fun start() {
            events.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, s: EventChannel.EventSink?) {
                    sink = s
                    if (s != null) {
                        for (m in queue) s.success(m)
                        queue.clear()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
            producer.setCallback(this)
            val surface = producer.surface
            player.setVideoSurface(surface)
            needsSurface = surface == null
            handler.post(ticker)
        }

        private fun send(m: Map<String, Any?>) {
            if (released) return
            val s = sink
            if (s != null) s.success(m) else if (queue.size < 200) queue.add(m)
        }

        private fun size(v: VideoSize): Pair<Int, Int> {
            var w = v.width
            val h = v.height
            if (w > 0 && v.pixelWidthHeightRatio > 0f && v.pixelWidthHeightRatio != 1f) {
                w = Math.max(1, Math.round(w * v.pixelWidthHeightRatio))
            }
            return Pair(w, h)
        }

        fun release() {
            if (released) return
            released = true
            handler.removeCallbacksAndMessages(null)
            try {
                player.removeListener(this)
                player.setVideoSurface(null)
                player.release()
            } catch (e: Exception) {
            }
            try {
                producer.setCallback(null)
                producer.release()
            } catch (e: Exception) {
            }
            events.setStreamHandler(null)
            sink = null
            queue.clear()
        }

        // ------------------------------------------------ SurfaceProducer.Callback

        override fun onSurfaceAvailable() {
            if (released) return
            if (needsSurface) {
                player.setVideoSurface(producer.surface)
                needsSurface = false
            }
        }

        override fun onSurfaceCleanup() {
            if (released) return
            player.setVideoSurface(null)
            needsSurface = true
        }

        // ------------------------------------------------ Player.Listener

        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_BUFFERING -> send(mapOf("e" to "buffering", "v" to true))
                Player.STATE_READY -> {
                    send(mapOf("e" to "buffering", "v" to false))
                    if (!readySent) {
                        readySent = true
                        val (w, h) = size(player.videoSize)
                        val d = player.duration
                        send(mapOf("e" to "ready", "w" to w, "h" to h, "d" to (if (d == C.TIME_UNSET) 0L else d)))
                    }
                }
                Player.STATE_ENDED -> {
                    send(mapOf("e" to "buffering", "v" to false))
                    send(mapOf("e" to "ended"))
                }
                else -> {}
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            send(mapOf("e" to "playing", "v" to isPlaying))
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            val (w, h) = size(videoSize)
            if (w > 0 && h > 0) send(mapOf("e" to "size", "w" to w, "h" to h))
        }

        override fun onRenderedFirstFrame() {
            send(mapOf("e" to "frame"))
        }

        override fun onPlayerError(error: PlaybackException) {
            if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                player.seekToDefaultPosition()
                player.prepare()
                return
            }
            val msg = "${error.errorCodeName}: ${error.message ?: ""}".trim()
            send(mapOf("e" to "error", "msg" to msg, "code" to error.errorCode))
        }
    }
}
