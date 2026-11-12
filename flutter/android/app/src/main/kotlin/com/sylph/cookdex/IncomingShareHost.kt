package com.sylph.cookdex

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Process
import android.provider.OpenableColumns
import android.widget.Toast
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Read-only intake. The provider enforces the sender's temporary URI grant. */
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

    fun accept(intent: Intent?, coldStart: Boolean): Boolean {
        if (intent == null || intent.action !in listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE, Intent.ACTION_VIEW)) return false
        if (outstanding >= 4) {
            Toast.makeText(activity, "Finish an import before sharing more recipes.", Toast.LENGTH_LONG).show()
            return true
        }
        outstanding++
        worker.execute {
            val type = IncomingShareTypes.normalize(intent.type)
            val result = try {
                read(intent, type)
            } catch (_: Exception) {
                failure(type.startsWith("image/"))
            } catch (_: OutOfMemoryError) {
                failure(type.startsWith("image/"))
            }
            activity.runOnUiThread { deliver(result + ("coldStart" to coldStart)) }
        }
        return true
    }

    @Suppress("DEPRECATION")
    private fun read(intent: Intent, type: String): Map<String, Any> {
        // Senders may duplicate the same stream in ClipData to carry the grant.
        val uris = linkedSetOf<Uri>()
        val multiple = intent.action == Intent.ACTION_SEND_MULTIPLE
        if (multiple) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let {
                require(it.size in 1..8)
                uris.addAll(it)
            }
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        }
        intent.data?.let(uris::add)
        val clip = intent.clipData
        // A browser's text share can attach a content URI for its preview.
        // Use the explicit shared page address without opening the thumbnail.
        val extraText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
        if (intent.action == Intent.ACTION_SEND && IncomingShareTypes.allowsMessage(type) &&
            !extraText.isNullOrBlank() && (uris.isEmpty() || IncomingShareTypes.isWebLink(extraText))) {
            return mapOf("text" to IncomingShareTypes.sharedMessage(extraText, null, null))
        }
        if (clip != null) {
            require(clip.itemCount in 1..8)
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(uris::add)
        }
        require(uris.size <= 8)
        if (uris.all { it.scheme == "https" || it.scheme == "http" }) {
            require(!multiple && IncomingShareTypes.allowsMessage(type))
            val message = IncomingShareTypes.sharedMessage(
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT),
                clip?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.text,
                uris.singleOrNull()?.toString(),
            )
            return mapOf("text" to message)
        }

        val resolver = activity.contentResolver
        val resolved = uris.map { uri ->
            require(uri.scheme == "content" && !uri.authority.isNullOrBlank())
            val authority = uri.authority!!.substringAfterLast('@')
            val provider = activity.packageManager.resolveContentProvider(authority, 0)
            require(provider?.applicationInfo?.uid != Process.myUid())
            IncomingShareTypes.normalize(resolver.getType(uri))
        }
        if (resolved.all { IncomingShareTypes.isPhoto(type, it) }) {
            return importer.prepareSharedPhotos(uris.toList())
        }
        require(!multiple && uris.size == 1)
        val uri = uris.single()
        val name = try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && it.moveToFirst()) it.getString(index) else null
            }
        } catch (_: UnsupportedOperationException) { null }
          catch (_: IllegalArgumentException) { null }
        val namedPath = uri.lastPathSegment?.takeIf { it.endsWith(".txt", ignoreCase = true) }
        require(IncomingShareTypes.isTextFile(type, resolved.single(), name?.takeIf { it.isNotBlank() } ?: namedPath))
        return mapOf("text" to importer.readSharedText(uri))
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
