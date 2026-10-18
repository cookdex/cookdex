package com.sylph.cookdex

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import java.io.File

/** Android 10+ app-owned images need no storage permission. */
class ImportPhotoMediaStore(private val context: Context) {
    fun publish(source: File, requestedName: String) {
        check(Build.VERSION.SDK_INT >= 29)
        val resolver = context.contentResolver
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val folder = "Pictures/cookdex/"
        fun exists(value: String): Boolean = resolver.query(
            collection, arrayOf(MediaStore.Images.Media._ID),
            "${MediaStore.Images.Media.RELATIVE_PATH} = ? AND ${MediaStore.Images.Media.DISPLAY_NAME} = ?",
            arrayOf(folder, value), null
        )?.use { it.moveToFirst() } ?: false
        val name = ImportPhotoArchive.availableName(requestedName, ::exists)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, folder)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = checkNotNull(resolver.insert(collection, values))
        try {
            checkNotNull(resolver.openOutputStream(uri)).use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            }
            check(resolver.update(uri, ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }, null, null) == 1)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }
}
