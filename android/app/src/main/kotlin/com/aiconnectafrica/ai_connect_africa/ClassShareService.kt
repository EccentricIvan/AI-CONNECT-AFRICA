package com.aiconnectafrica.ai_connect_africa

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps class sharing alive while the teacher's (or a sharing student's)
 * phone is in a pocket or on another app.
 *
 * Class sync's server (`ClassShareServer`) runs in the Flutter isolate of
 * this process. Without a foreground service, Android freezes or kills the
 * process soon after the app leaves the screen, and Wi-Fi power saving drops
 * incoming connections. While sharing, this service:
 *  - shows an ongoing "Sharing class notes" notification
 *    (type `connectedDevice`: serving devices on the local Wi-Fi);
 *  - holds a Wi-Fi lock and a partial wake lock, released when it stops.
 *
 * Started and stopped from Dart over `ai_connect_africa/class_share`
 * ([MainActivity]); nothing here touches the network itself.
 */
class ClassShareService : Service() {
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(
            intent?.getStringExtra(EXTRA_TEXT) ?: DEFAULT_TEXT,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        acquireLocks()
        // If Android kills the process anyway, the Dart server is gone too:
        // don't come back with an empty notification.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The app was swiped away: the server died with it.
        stopSelf()
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun acquireLocks() {
        if (wifiLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifi.createWifiLock(mode, "otic:class-share").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "otic:class-share",
            ).apply {
                setReferenceCounted(false)
                // Never forever: the Dart side stops the service when sharing
                // ends, and a lesson-length cap guards against a missed stop.
                acquire(MAX_WAKE_MS)
            }
        }
    }

    private fun releaseLocks() {
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun buildNotification(text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Class sharing",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while this device shares class notes on the Wi-Fi"
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Sharing class notes")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "otic_class_share"
        private const val NOTIFICATION_ID = 4107
        private const val EXTRA_TEXT = "text"
        private const val DEFAULT_TEXT = "Learners on this Wi-Fi can sync with this device."
        private const val MAX_WAKE_MS = 3L * 60 * 60 * 1000

        fun start(context: Context, text: String?) {
            val intent = Intent(context, ClassShareService::class.java)
            if (text != null) intent.putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ClassShareService::class.java))
        }
    }
}
