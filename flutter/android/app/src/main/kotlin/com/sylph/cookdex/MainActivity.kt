package com.sylph.cookdex

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var importHost: ImportHost? = null
    private var incomingShareHost: IncomingShareHost? = null
    private var exportHost: ExportHost? = null
    private var pickerResult: MethodChannel.Result? = null
    private val fileWorker = Executors.newSingleThreadExecutor()
    private val zipRequest = 4505
    private var networkPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importHost = ImportHost(this)
        exportHost = ExportHost(this)
        incomingShareHost = IncomingShareHost(this, importHost!!,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sylph.cookdex.dev/incoming"))
        if (incomingShareHost!!.accept(intent, true)) setIntent(Intent(Intent.ACTION_MAIN))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sylph.cookdex.dev/export")
            .setMethodCallHandler { call, result -> exportHost!!.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sylph.cookdex.dev/import")
            .setMethodCallHandler { call, result -> importHost!!.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sylph.cookdex.dev/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "applicationId" -> result.success(packageName)
                    "deviceName" -> result.success(Build.MODEL)
                    "appVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success("${info.versionName}+$code")
                    }
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success("${applicationInfo.loadLabel(packageManager)}\nVersion: ${info.versionName}\nBuild: $code\nDevice: ${Build.MODEL}\nAndroid: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
                    }
                    "hasLocalNetwork" -> result.success(hasLocalNetwork())
                    "requestLocalNetwork" -> {
                        val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                        if (hasLocalNetwork()) result.success(true)
                        else if (networkPermission != null) result.error("busy", "Permission request already open.", null)
                        else { networkPermission = result; requestPermissions(arrayOf(permission), 4509) }
                    }
                    "privateRoot" -> {
                        // OS-owned package directory, with no old-app resolver.
                        val root = File(filesDir, "flutter-v1")
                        if (!root.exists() && !root.mkdirs()) result.error("storage", "Cannot open private storage.", null)
                        else result.success(root.absolutePath)
                    }
                    "pickRecipeZip" -> {
                        if (pickerResult != null) result.error("busy", "A file picker is already open.", null)
                        else {
                            pickerResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/zip"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream"))
                            }
                            try { startActivityForResult(intent, zipRequest) }
                            catch (_: Exception) {
                                pickerResult = null
                                result.error("picker", "Unable to open the file picker.", null)
                            }
                        }
                    }
                    "keepScreenOn" -> {
                        if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "backgroundTask" -> { moveTaskToBack(true); result.success(null) }
                    "wallpaperColors" -> result.success(WallpaperColors.read(this, call.arguments == "dark"))
                    "openSource" -> {
                        val uri = Uri.parse(call.arguments as? String ?: "")
                        if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank()) result.error("source", "Invalid source link.", null)
                        else try { startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(null) }
                        catch (_: Exception) { result.error("source", "No application could open the source link.", null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (incomingShareHost?.accept(intent, false) == true) setIntent(Intent(Intent.ACTION_MAIN))
    }

    private fun hasLocalNetwork(): Boolean = Build.VERSION.SDK_INT < 37 ||
        checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") == android.content.pm.PackageManager.PERMISSION_GRANTED

    @Deprecated("Activity result compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (importHost?.onActivityResult(requestCode, resultCode, data) == true) return
        if (exportHost?.onActivityResult(requestCode, resultCode, data) == true) return
        if (requestCode != zipRequest) return
        val callback = pickerResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pickerResult = null
            callback.success(null)
            return
        }
        fileWorker.execute {
            try {
                // Bound bytes before crossing the channel. Rust validates the whole archive.
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    var count: Int
                    while (input.read(buffer).also { count = it } != -1) {
                        if (output.size().toLong() + count > 64L * 1024 * 1024) throw IllegalArgumentException("large")
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException("unreadable")
                runOnUiThread { if (pickerResult === callback) { pickerResult = null; callback.success(bytes) } }
            } catch (_: Exception) {
                runOnUiThread { if (pickerResult === callback) { pickerResult = null; callback.error("zip", "Cannot read ZIP (maximum 64 MiB).", null) } }
            }
        }
    }

    override fun onPause() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onPause()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4509) {
            networkPermission?.success(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED)
            networkPermission = null
        }
    }

    override fun onDestroy() {
        networkPermission?.success(false); networkPermission = null
        incomingShareHost?.close()
        importHost?.close()
        exportHost?.close()
        pickerResult?.error("cancelled", "File selection was cancelled.", null)
        pickerResult = null
        fileWorker.shutdownNow()
        super.onDestroy()
    }
}
