package com.sylph.cookdex

import java.io.File
import java.util.UUID

/** Private full-resolution photo copies live here; prepared AI images never do. */
class ImportPhotoArchive(private val directory: File) {
    fun retain(capture: File): String {
        check(directory.isDirectory || directory.mkdirs())
        val id = UUID.randomUUID().toString() + ".jpg"
        capture.copyTo(File(directory, id))
        return id
    }
    fun retainPhoto(bytes: ByteArray, toFullResolutionJpeg: (ByteArray) -> ByteArray): String {
        // Keep JPEG originals byte-for-byte; other formats need a real JPEG for .jpg publication.
        val jpeg = bytes.size >= 3 && bytes[0] == 0xff.toByte() &&
            bytes[1] == 0xd8.toByte() && bytes[2] == 0xff.toByte()
        val original = if (jpeg) bytes else toFullResolutionJpeg(bytes)
        check(directory.isDirectory || directory.mkdirs())
        val id = UUID.randomUUID().toString() + ".jpg"
        File(directory, id).writeBytes(original)
        return id
    }
    private fun file(id: String): File {
        require(id.matches(Regex("[0-9a-f-]{36}\\.jpg")))
        return File(directory, id)
    }
    fun discard(ids: List<String>) {
        ids.forEach { id -> runCatching { file(id).delete() } }
    }
    fun clear() {
        directory.listFiles()?.filter { it.isFile }?.forEach { check(it.delete()) }
    }
    /** Returns failed card numbers; a successful publication consumes its original. */
    fun save(ids: List<String>, title: String, publish: (File, String) -> Unit): List<Int> {
        require(ids.size <= 8 && ids.distinct().size == ids.size)
        val failures = mutableListOf<Int>()
        ids.forEachIndexed { index, id ->
            try {
                val source = file(id)
                check(source.isFile)
                publish(source, photoName(title, index + 1))
                source.delete()
            } catch (_: Exception) { failures.add(index + 1) }
        }
        return failures
    }
    companion object {
        fun availableName(requested: String, exists: (String) -> Boolean): String {
            var name = requested
            var duplicate = 2
            while (exists(name)) { name = requested.removeSuffix(".jpg") + " (" + duplicate++ + ").jpg" }
            return name
        }
        fun photoName(title: String, card: Int): String {
            val safe = title.replace(Regex("[\\x00-\\x1f\\x7f<>:\"/\\\\|?*]"), "_")
                .trim().trimEnd('.').take(100).ifEmpty { "Recipe" }
            return "$safe - card $card.jpg"
        }
    }
}
