package com.urbaneye.urbaneye_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.ClipData
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannel = "urbaneye/system_notifications"
    private val notificationChannelId = "environmental_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "urbaneye/app_updates")
            .setMethodCallHandler { call, result ->
                try {
                    val directory = File(cacheDir, "updates").apply { mkdirs() }.canonicalFile
                    when (call.method) {
                        "cacheDirectory" -> result.success(directory.path)
                        "install" -> {
                            val path = call.argument<String>("path")
                                ?: throw IllegalArgumentException("APK ausente")
                            val file = File(path).canonicalFile
                            require(file.parentFile == directory && file.name == "update.apk" && file.isFile) {
                                "APK fora do cache privado"
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")))
                                result.error("permission_required", "Autorize esta fonte e tente novamente.", null)
                            } else {
                                val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    clipData = ClipData.newRawUri("APK", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("installer_unavailable", error.message, null)
                }
            }
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
