package com.vitorhugo.sonicrelay.sonic_relay.background

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.vitorhugo.sonicrelay.sonic_relay.MainActivity
import com.vitorhugo.sonicrelay.sonic_relay.R

/**
 * A `mediaPlayback` foreground service that keeps the viewer process (WebRTC
 * receiver, signaling, audio playback) alive while the app is backgrounded
 * during an active stream. It shows a persistent notification with Open, Stop,
 * and (optionally) Reconnect actions, forwarding taps to Dart via
 * [ForegroundBridge]. No token or session data is ever placed in intents/extras.
 */
class SonicRelayForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
                val showReconnect = intent.getBooleanExtra(EXTRA_RECONNECT, false)
                startForegroundCompat(buildNotification(title, body, showReconnect))
            }
            ACTION_NOTIF_OPEN -> {
                ForegroundBridge.emit("open")
                launchMainActivity()
            }
            ACTION_NOTIF_STOP -> ForegroundBridge.emit("stop")
            ACTION_NOTIF_RECONNECT -> ForegroundBridge.emit("reconnect")
            ACTION_STOP -> {
                val endedNotice = intent.getStringExtra(EXTRA_ENDED_NOTICE)
                stopForegroundCompat()
                if (!endedNotice.isNullOrBlank()) postEndedNotice(endedNotice)
                stopSelf()
            }
        }
        // Do not auto-restart if the system kills us. The active stream state
        // (peer connection, signaling socket, audio) lives in the Dart isolate
        // hosted by the process-lifetime FlutterEngine (see
        // SonicRelayApplication), not in this service, so a bare restart here
        // could not resurrect it anyway — the user starts streams intentionally
        // and Dart re-drives the service on the next one.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // Intentionally a no-op: this service (and the process/engine it keeps
        // alive) must keep running when the user swipes SonicRelay away from
        // recent apps while a stream is active — that's the whole point of
        // promoting to a foreground service. The default Service behavior
        // already doesn't stop the service on task removal, and the manifest
        // sets android:stopWithTask="false" explicitly; this override exists so
        // the intent is documented and a future edit doesn't accidentally add a
        // stopSelf() here. See issue #22.
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(
        title: String,
        body: String,
        showReconnect: Boolean,
    ): Notification {
        ensureChannel()
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(actionIntent(ACTION_NOTIF_OPEN))
            .addAction(0, "Open", actionIntent(ACTION_NOTIF_OPEN))
            .addAction(0, "Stop", actionIntent(ACTION_NOTIF_STOP))
        if (showReconnect) {
            builder.addAction(0, "Reconnect", actionIntent(ACTION_NOTIF_RECONNECT))
        }
        return builder.build()
    }

    private fun postEndedNotice(text: String) {
        ensureChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(DEFAULT_TITLE)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(actionIntent(ACTION_NOTIF_OPEN))
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(ENDED_NOTICE_ID, notification)
    }

    private fun actionIntent(action: String): PendingIntent {
        val intent = Intent(this, SonicRelayForegroundService::class.java).apply {
            this.action = action
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getService(this, action.hashCode(), intent, flags)
    }

    private fun launchMainActivity() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Background streaming",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while SonicRelay keeps playing audio in the background."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.vitorhugo.sonicrelay.action.START"
        const val ACTION_UPDATE = "com.vitorhugo.sonicrelay.action.UPDATE"
        const val ACTION_STOP = "com.vitorhugo.sonicrelay.action.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_RECONNECT = "showReconnect"
        const val EXTRA_ENDED_NOTICE = "endedNotice"

        private const val ACTION_NOTIF_OPEN = "com.vitorhugo.sonicrelay.action.NOTIF_OPEN"
        private const val ACTION_NOTIF_STOP = "com.vitorhugo.sonicrelay.action.NOTIF_STOP"
        private const val ACTION_NOTIF_RECONNECT =
            "com.vitorhugo.sonicrelay.action.NOTIF_RECONNECT"

        private const val CHANNEL_ID = "sonicrelay_background_stream"
        private const val NOTIFICATION_ID = 4201
        private const val ENDED_NOTICE_ID = 4202
        private const val DEFAULT_TITLE = "SonicRelay"
    }
}
