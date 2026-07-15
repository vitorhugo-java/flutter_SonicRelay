package com.vitorhugo.sonicrelay.sonic_relay

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.vitorhugo.sonicrelay.sonic_relay.background.ForegroundBridge
import com.vitorhugo.sonicrelay.sonic_relay.background.SonicRelayForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Attach to the process-lifetime engine pre-warmed in [SonicRelayApplication]
    // instead of letting the framework create one scoped to this activity. A
    // non-null cached engine id also makes the base class's
    // shouldDestroyEngineWithHost() return false, so destroying this activity
    // (e.g. the task being swiped away) no longer tears down the Dart isolate
    // and kills the active stream. See issue #22.
    override fun getCachedEngineId(): String = SonicRelayApplication.ENGINE_ID

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    ensureNotificationPermission()
                    val intent = Intent(this, SonicRelayForegroundService::class.java).apply {
                        action = SonicRelayForegroundService.ACTION_START
                        putExtra(SonicRelayForegroundService.EXTRA_TITLE, call.argument<String>("title"))
                        putExtra(SonicRelayForegroundService.EXTRA_BODY, call.argument<String>("body"))
                        putExtra(
                            SonicRelayForegroundService.EXTRA_RECONNECT,
                            call.argument<Boolean>("showReconnect") ?: false,
                        )
                    }
                    // applicationContext, not this activity: these channel handlers
                    // stay registered on the engine's messenger (which outlives this
                    // activity instance) and this method can legitimately still be
                    // invoked from Dart while no activity is attached.
                    ContextCompat.startForegroundService(applicationContext, intent)
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, SonicRelayForegroundService::class.java).apply {
                        action = SonicRelayForegroundService.ACTION_STOP
                        putExtra(
                            SonicRelayForegroundService.EXTRA_ENDED_NOTICE,
                            call.argument<String>("endedNotice"),
                        )
                    }
                    // A running foreground service permits starting a service even
                    // from the background, so this is safe while backgrounded.
                    applicationContext.startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ForegroundBridge.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    ForegroundBridge.detach()
                }
            },
        )
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "sonicrelay/foreground"
        private const val EVENT_CHANNEL = "sonicrelay/foreground/events"
        private const val REQ_NOTIFICATIONS = 4210
    }
}
