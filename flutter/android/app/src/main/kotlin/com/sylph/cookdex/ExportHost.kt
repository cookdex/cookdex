package com.sylph.cookdex

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Flutter-only user-requested exports; no database paths cross this channel. */
class ExportHost(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    @Volatile private var closed = false
    companion object { const val SAVE_TEXT = 4801; const val MAX_BYTES = 64 * 1024 * 1024 }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("cancelled", "Export was cancelled.", null); return }
        val zip = call.method == "saveZip"
        val text = call.argument<String>("text") ?: ""
        val bytes = if (zip) call.argument<ByteArray>("bytes") ?: run { result.error("export", "ZIP is missing.", null); return } else text.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BYTES) { result.error("limit", "Text export exceeds 64 MiB.", null); return }
        when (call.method) {
            "shareText" -> {
                // Binder transactions include the chooser and receiving intent.
                if (bytes.size > 256 * 1024) {
                    result.error("limit", "This recipe is too large for message sharing. Share a text file instead.", null)
                    return
                }
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("title") ?: "Recipe")
                }
                try {
                    activity.startActivity(Intent.createChooser(send, call.argument<String>("title") ?: "Share recipe"))
                    result.success("opened")
                } catch (_: android.content.ActivityNotFoundException) {
                    result.error("unavailable", "System sharing is unavailable.", null)
                } catch (_: Exception) { result.error("share", "Could not open sharing.", null) }
            }
            "shareFile" -> {
                val filename = filename(call) ?: run { result.error("filename", "Invalid export filename.", null); return }
                worker.execute {
                    try {
                        val root = File(activity.cacheDir, "export-text")
                        check(root.exists() || root.mkdirs())
                        // Expire old shares only; new receiver grants can outlive the chooser.
                        root.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 7L * 86400000 }
                            ?.forEach { it.deleteRecursively() }
                        val directory = File(root, UUID.randomUUID().toString())
                        check(directory.mkdir())
                        val file = File(directory, filename)
                        file.outputStream().use { it.write(bytes); it.flush() }
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.import-files", file)
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            clipData = ClipData.newRawUri(filename, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        activity.runOnUiThread {
                            if (!closed) try {
                                activity.startActivity(Intent.createChooser(send, "Share recipe file").apply {
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                })
                                result.success("opened")
                            } catch (_: android.content.ActivityNotFoundException) {
                                result.error("unavailable", "System sharing is unavailable.", null)
                            } catch (_: Exception) { result.error("share", "Could not share the text file.", null) }
                        }
                    } catch (_: Exception) {
                        activity.runOnUiThread { if (!closed) result.error("share", "Could not prepare the text file.", null) }
                    }
                }
            }
            "saveText", "saveZip" -> {
                val filename = filename(call) ?: run { result.error("filename", "Invalid export filename.", null); return }
                if (pending != null) { result.error("busy", "An export destination picker is already open.", null); return }
                pending = result
                pendingBytes = bytes
                try {
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (zip) "application/zip" else "text/plain"
                        putExtra(Intent.EXTRA_TITLE, filename)
                    }, SAVE_TEXT)
                } catch (_: Exception) {
                    pending = null; pendingBytes = null
                    result.error("save", "Could not open the export destination picker.", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun filename(call: MethodCall): String? {
        val value = call.argument<String>("filename") ?: return null
        return value.takeIf { it.length in 1..180 && it.endsWith(if (call.method == "saveZip") ".zip" else ".txt") && it.none { char -> char.code < 32 || char in "<>:\"/\\|?*" } }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_TEXT) return false
        val callback = pending ?: return true
        val bytes = pendingBytes ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null; pendingBytes = null
            callback.success("cancelled")
            return true
        }
        worker.execute {
            try {
                // Explicit truncation; only report saved once write and close both succeed.
                activity.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                    output.write(bytes); output.flush()
                } ?: throw IllegalStateException("Destination could not be opened")
                activity.runOnUiThread {
                    if (!closed && pending === callback) {
                        pending = null; pendingBytes = null; callback.success("saved")
                    }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (!closed && pending === callback) {
                        pending = null; pendingBytes = null
                        callback.error("save", "Could not write the text file.", null)
                    }
                }
            }
        }
        return true
    }

    fun close() {
        closed = true
        pending?.success("cancelled")
        pending = null; pendingBytes = null
        worker.shutdownNow()
    }
}
