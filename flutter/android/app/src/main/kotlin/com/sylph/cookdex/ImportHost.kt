package com.sylph.cookdex

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Flutter-only import host. Secrets never cross the channel on read. */
class ImportHost(private val activity: Activity) {
    private val worker = Executors.newSingleThreadExecutor()
    private val deadlineWorker = Executors.newSingleThreadScheduledExecutor()
    private val prefs = activity.getSharedPreferences("cookdex_flutter_v1_smart", Activity.MODE_PRIVATE)
    private var picker: MethodChannel.Result? = null
    private var pickerLimit = 8
    private var cameraFile: File? = null
    @Volatile private var connection: HttpURLConnection? = null
    @Volatile private var generation = 0
    private val originals = ImportPhotoArchive(File(activity.filesDir, "import-originals"))
    companion object {
        const val TEXT = 4701; const val PHOTOS = 4702; const val CAMERA = 4703
        private var cleanedThisProcess = false
    }
    init {
        synchronized(ImportHost::class.java) {
            if (!cleanedThisProcess) {
                originals.clear()
                File(activity.cacheDir, "import-camera").listFiles()?.filter { it.isFile }?.forEach { it.delete() }
                cleanedThisProcess = true
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canSavePhotos" -> result.success(android.os.Build.VERSION.SDK_INT >= 29)
            "discardOriginals" -> background(result, "Could not discard temporary photos.") {
                originals.discard(call.argument<List<String>>("ids") ?: emptyList()); null
            }
            "savePhotos" -> background(result, "Recipe saved, but photos could not be saved to the device.") {
                check(android.os.Build.VERSION.SDK_INT >= 29)
                originals.save(call.argument<List<String>>("ids") ?: emptyList(), call.argument<String>("title") ?: "Recipe") { file, name ->
                    ImportPhotoMediaStore(activity).publish(file, name)
                }
            }
            "settings" -> result.success(mapOf("hasKey" to prefs.contains("key"), "model" to prefs.getString("model", "gemini-3.5-flash-lite")))
            "saveSettings" -> background(result) {
                val model = call.argument<String>("model")?.trim() ?: ""
                val key = call.argument<String>("key")?.trim() ?: ""
                require(model.matches(Regex("[A-Za-z0-9._-]{1,120}")))
                require(key.length <= 1024 && key.none { it.code < 33 || it.code > 126 })
                val editor = prefs.edit().putString("model", model)
                if (key.isNotEmpty()) editor.putString("key", encrypt(key))
                check(editor.commit())
                null
            }
            "removeKey" -> background(result) { check(prefs.edit().remove("key").commit()); null }
            "pickText" -> pick(result, TEXT, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE); type = "text/plain"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/octet-stream"))
            })
            "pickPhotos" -> {
                pickerLimit = (call.argument<Int>("maxCount") ?: 8).coerceIn(0, 8)
                if (pickerLimit == 0) { result.error("limit", "Choose at most 8 photos.", null); return }
                if (call.argument<Boolean>("camera") == true) {
                    try {
                        val directory = File(activity.cacheDir, "import-camera").apply { mkdirs() }
                        // Only our temporary capture directory, never a user photo.
                        directory.listFiles()?.filter { it.isFile }?.forEach { it.delete() }
                        cameraFile = File.createTempFile("capture-", ".jpg", directory)
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.import-files", cameraFile!!)
                        pick(result, CAMERA, Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                            putExtra(MediaStore.EXTRA_OUTPUT, uri)
                            clipData = android.content.ClipData.newRawUri("Recipe photo", uri)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        })
                    } catch (_: Exception) { cameraFile?.delete(); cameraFile = null; result.error("camera", "Unable to open the camera.", null) }
                } else pick(result, PHOTOS, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE); type = "image/*"; putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                })
            }
            "providerRequest" -> {
                val body = call.arguments as? ByteArray
                val token = generation
                if (body == null || body.size >= 16 * 1024 * 1024) result.error("limit", "Import request is too large.", null)
                else background(result, "Smart Import could not connect. Try again.", provider = true) {
                    if (token != generation) throw IllegalStateException()
                    val encrypted = prefs.getString("key", null) ?: throw ImportRequestFailure("Add a Gemini key to use AI import.")
                    val key = try { decrypt(encrypted) } catch (_: Exception) { throw ImportRequestFailure("The saved Gemini key could not be read. Save it again in AI settings.") }
                    val request = URL("https://generativelanguage.googleapis.com/v1beta/interactions").openConnection() as HttpURLConnection
                    connection = request
                    val timedOut = java.util.concurrent.atomic.AtomicBoolean(false)
                    val deadline = deadlineWorker.schedule({ timedOut.set(true); request.disconnect() }, 180, TimeUnit.SECONDS)
                    try {
                        request.instanceFollowRedirects = false
                        request.requestMethod = "POST"
                        request.connectTimeout = 30000; request.readTimeout = 180000
                        request.doOutput = true
                        request.setRequestProperty("Content-Type", "application/json")
                        request.setRequestProperty("x-goog-api-key", key)
                        request.setFixedLengthStreamingMode(body.size)
                        request.outputStream.use { it.write(body) }
                        val status = request.responseCode
                        val response = (if (status in 200..299) request.inputStream else request.errorStream)?.use { try { bounded(it, 2 * 1024 * 1024) } catch (_: IllegalArgumentException) { throw ImportRequestFailure("Gemini’s reply exceeded the 2 MiB response limit.") } } ?: ByteArray(0)
                        if (token != generation) throw IllegalStateException()
                        val safeResponse = response.toString(Charsets.UTF_8).replace(key, "[redacted key]").replace(Regex("AIza[0-9A-Za-z_-]+"), "[redacted key]").toByteArray(Charsets.UTF_8)
                        mapOf("status" to status, "bytes" to safeResponse)
                    } catch (error: Exception) {
                        if (timedOut.get()) throw ImportRequestFailure("The Gemini request timed out after 3 minutes. Try again.")
                        throw error
                    } finally { deadline.cancel(false); request.disconnect(); if (connection === request) connection = null }
                }
            }
            "cancel" -> { generation++; connection?.disconnect(); connection = null; result.success(null) }
            else -> result.notImplemented()
        }
    }
    private class ImportRequestFailure(message: String) : Exception(message)
    private fun background(result: MethodChannel.Result, message: String = "Smart Import settings could not be saved.", provider: Boolean = false, action: () -> Any?) {
        worker.execute {
            try { val value = action(); activity.runOnUiThread { result.success(value) } }
            catch (error: Exception) {
                val reason = if (!provider) message else when (error) {
                    is ImportRequestFailure -> error.message ?: message
                    is java.net.SocketTimeoutException -> "The Gemini connection timed out. Try again."
                    is java.net.UnknownHostException -> "Google’s address could not be found. Check your connection."
                    is javax.net.ssl.SSLException -> "Google’s secure connection could not be verified."
                    is java.net.ConnectException -> "Could not connect to Google. Check your connection and try again."
                    is java.io.IOException -> "The connection to Google was interrupted. Try again."
                    else -> message
                }
                activity.runOnUiThread { result.error("import", reason, null) }
            }
        }
    }
    private fun pick(result: MethodChannel.Result, code: Int, intent: Intent) {
        if (picker != null) { result.error("busy", "A picker is already open.", null); return }
        picker = result
        try { activity.startActivityForResult(intent, code) }
        catch (_: Exception) { picker = null; result.error("picker", "Unable to open the picker.", null) }
    }
    fun onActivityResult(code: Int, status: Int, data: Intent?): Boolean {
        if (code !in listOf(TEXT, PHOTOS, CAMERA)) return false
        val result = picker ?: return true
        if (status != Activity.RESULT_OK) {
            picker = null; cameraFile?.delete(); cameraFile = null; result.success(null); return true
        }
        val capture = cameraFile
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip -> for (index in 0 until clip.itemCount.coerceAtMost(9)) uris.add(clip.getItemAt(index).uri) }
        if (uris.isEmpty()) data?.data?.let { uris.add(it) }
        worker.execute {
            try {
                val value: Any = if (code == TEXT) {
                    val uri = uris.firstOrNull() ?: throw IllegalArgumentException()
                    val bytes = activity.contentResolver.openInputStream(uri)?.use { bounded(it, 5 * 1024 * 1024) } ?: throw IllegalArgumentException()
                    Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString().removePrefix("\uFEFF")
                } else {
                    val photos = mutableListOf<ByteArray>(); val originalIds = mutableListOf<String?>(); val errors = mutableListOf<String>()
                    if (uris.size > pickerLimit) errors.add("Choose at most 8 photos. Extra selections were skipped.")
                    val inputs: List<() -> InputStream> = if (code == CAMERA) listOf({ (capture ?: throw IllegalArgumentException()).inputStream() })
                        else uris.take(pickerLimit).map { uri -> { activity.contentResolver.openInputStream(uri) ?: throw IllegalArgumentException() } }
                    inputs.forEachIndexed { index, open ->
                        try {
                            val bytes = open().use { bounded(it, 25 * 1024 * 1024) }
                            val prepared = preparePhoto(bytes)
                            val originalId = if (code == CAMERA) originals.retain(checkNotNull(capture))
                                else originals.retainPhoto(bytes) { preparePhoto(it, fullResolution = true) }
                            photos.add(prepared); originalIds.add(originalId)
                        }
                        catch (_: Exception) { errors.add("Photo ${index + 1} could not be read (25 MiB / 80 MP maximum).") }
                        catch (_: OutOfMemoryError) { errors.add("Photo ${index + 1} could not fit in memory. Choose a smaller photo.") }
                    }
                    mapOf("photos" to photos, "originalIds" to originalIds, "errors" to errors)
                }
                activity.runOnUiThread { if (picker === result) { picker = null; result.success(value) } }
            } catch (_: Exception) {
                activity.runOnUiThread { if (picker === result) { picker = null; result.error("picker", "Cannot read this file (UTF-8 .txt, maximum 5 MiB).", null) } }
            } finally { capture?.delete(); if (cameraFile === capture) cameraFile = null }
        }
        return true
    }
    /** Same decoder and bounds as Gallery; incoming shares never read credentials. */
    fun prepareSharedPhotos(uris: List<Uri>): Map<String, Any> {
        require(uris.size in 1..8)
        val photos = mutableListOf<ByteArray>()
        val originalIds = mutableListOf<String>()
        var payload = 0L
        try {
            for (uri in uris) {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { bounded(it, 25 * 1024 * 1024) }
                    ?: throw IllegalArgumentException()
                val photo = preparePhoto(bytes)
                payload += ((photo.size.toLong() + 2) / 3) * 4
                require(payload <= 12L * 1024 * 1024)
                originalIds.add(originals.retainPhoto(bytes) { preparePhoto(it, fullResolution = true) })
                photos.add(photo)
            }
            return mapOf("photos" to photos, "originalIds" to originalIds, "errors" to emptyList<String>())
        } catch (error: Throwable) {
            originals.discard(originalIds)
            throw error
        }
    }
    fun readSharedText(uri: Uri): String {
        val bytes = activity.contentResolver.openInputStream(uri)?.use { bounded(it, 5 * 1024 * 1024) }
            ?: throw IllegalArgumentException()
        return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
    }

    private fun preparePhoto(bytes: ByteArray, fullResolution: Boolean = false): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 80_000_000L)
        val orientation = try { ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
        var sample = 1
        while (!fullResolution && maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 2000) sample *= 2
        var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }) ?: throw IllegalArgumentException()
        try {
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            }
            val ratio = if (fullResolution) 1f else minOf(1f, 2000f / maxOf(bitmap.width, bitmap.height))
            matrix.postScale(ratio, ratio)
            val oriented = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (oriented !== bitmap) { bitmap.recycle(); bitmap = oriented }
            return ByteArrayOutputStream().use { output ->
                // Re-encoding raster pixels creates a fresh JPEG without EXIF/GPS.
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, if (fullResolution) 95 else 88, output)); output.toByteArray()
            }
        } finally { bitmap.recycle() }
    }
    private fun bounded(input: InputStream, max: Int): ByteArray {
        val output = ByteArrayOutputStream(); val buffer = ByteArray(65536)
        while (true) { val n = input.read(buffer); if (n < 0) break; require(output.size().toLong() + n <= max); output.write(buffer, 0, n) }
        return output.toByteArray()
    }
    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "cookdex_flutter_v1_gemini"
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }
    private fun decrypt(value: String): String {
        val bytes = Base64.decode(value, Base64.NO_WRAP); require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, bytes.copyOfRange(0, 12))) }
        return String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }
    fun close() {
        generation++; connection?.disconnect(); picker?.error("cancelled", "Selection cancelled.", null); picker = null
        cameraFile?.delete(); cameraFile = null; worker.shutdownNow(); deadlineWorker.shutdownNow()
    }
}
