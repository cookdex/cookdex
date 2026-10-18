package com.sylph.cookdex

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Bounded, read-only intake. No file paths or recipes are logged or trusted. */
class IncomingShareHost(
    private val activity: Activity,
    private val importer: ImportHost,
    private val channel: MethodChannel,
) {
    private val worker = Executors.newSingleThreadExecutor()
    private val pending = ArrayDeque<Map<String, Any>>()
    private var outstanding = 0
    private var closed = false
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> result.success(if (pending.isEmpty()) null else pending.removeFirst().also { outstanding-- })
                "finishIfEmpty" -> {
                    val empty = outstanding == 0
                    result.success(empty)
                    if (empty) activity.finish()
                }
                else -> result.notImplemented()
            }
        }
    }
    @Suppress("DEPRECATION")
    fun accept(intent: Intent?, coldStart: Boolean): Boolean {
        if (intent?.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE, Intent.ACTION_VIEW)) return false
        if (outstanding >= 4) {
            Toast.makeText(activity, "Finish an import before sharing more recipes.", Toast.LENGTH_LONG).show()
            return true
        }
        outstanding++
        try {
            val type = intent!!.type.orEmpty()
            val images = type.startsWith("image/")
            require(images || type in listOf("text/plain", "application/octet-stream"))
            val uris = mutableListOf<Uri>()
            if (intent.action == Intent.ACTION_VIEW) intent.data?.let { uris.add(it) }
            else if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.take(9)?.let { uris.addAll(it) }
            } else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            if (uris.isEmpty()) intent.clipData?.let { clip ->
                for (i in 0 until minOf(clip.itemCount, 9)) clip.getItemAt(i).uri?.let { uris.add(it) }
            }
            require(uris.size <= if (images) 8 else 1)
            uris.forEach {
                require(it.scheme == "content" && !it.authority.orEmpty().startsWith(activity.packageName))
            }
            val text = if (!images && uris.isEmpty()) intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() else null
            require(text == null || text.toByteArray(Charsets.UTF_8).size <= 5 * 1024 * 1024)
            worker.execute {
                val result: Map<String, Any> = try {
                    when {
                        images -> importer.prepareSharedPhotos(uris)
                        uris.isNotEmpty() -> {
                            if (type == "application/octet-stream") {
                                val filename = activity.contentResolver.query(uris.single(), arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                                    if (it.moveToFirst()) it.getString(0) else ""
                                }.orEmpty()
                                require(filename.endsWith(".txt", ignoreCase = true))
                            }
                            mapOf("text" to importer.readSharedText(uris.single()))
                        }
                        text != null -> mapOf("text" to text)
                        else -> throw IllegalArgumentException()
                    }
                } catch (_: Exception) { failure(images) }
                  catch (_: OutOfMemoryError) { failure(images) }
                activity.runOnUiThread { deliver(result + ("coldStart" to coldStart)) }
            }
        } catch (_: Exception) { deliver(failure(false) + ("coldStart" to coldStart)) }
        return true
    }
    private fun failure(images: Boolean): Map<String, Any> = mapOf("error" to if (images)
        "Could not read the shared photos. Choose up to 8 images (25 MB / 80 MP each, 12 MB prepared total)."
        else "Could not read the shared text. Choose a UTF-8 .txt file of 5 MB or less.")
    private fun deliver(value: Map<String, Any>) {
        if (closed) return
        pending.addLast(value)
        channel.invokeMethod("ready", null)
    }
    fun close() { closed = true; pending.clear(); channel.setMethodCallHandler(null); worker.shutdownNow() }
}
