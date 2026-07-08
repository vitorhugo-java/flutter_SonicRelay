package com.vitorhugo.sonicrelay.sonic_relay.background

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Process-wide bridge that forwards foreground-service notification actions
 * (open / stop / reconnect) from [SonicRelayForegroundService] back to Dart over
 * an [EventChannel]. The sink is owned by the Flutter engine (MainActivity), so
 * events are always delivered on the main thread.
 */
object ForegroundBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun attach(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun detach() {
        eventSink = null
    }

    /** Emits an action string ("open" | "stop" | "reconnect") to Dart. */
    fun emit(action: String) {
        mainHandler.post { eventSink?.success(action) }
    }
}
