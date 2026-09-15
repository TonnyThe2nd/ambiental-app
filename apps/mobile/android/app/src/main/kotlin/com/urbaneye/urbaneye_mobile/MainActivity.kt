package com.urbaneye.urbaneye_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannel = "urbaneye/system_notifications"
    private val notificationChannelId = "environmental_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "show") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val title = call.argument<String>("title") ?: "Novo alerta ambiental"
                val body = call.argument<String>("body") ?: "Há uma ocorrência próxima de você."
                val id = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                showNotification(id, title, body)
                result.success(null)
            }
    }

    private fun showNotification(id: Int, title: String, body: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                notificationChannelId,
                "Alertas ambientais",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val notification = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()
        manager.notify(id, notification)
    }
}
