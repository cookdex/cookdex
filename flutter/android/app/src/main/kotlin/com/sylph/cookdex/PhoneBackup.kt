package com.sylph.cookdex

import java.io.*
import java.security.DigestInputStream
import java.security.DigestOutputStream
import java.security.MessageDigest

/** A single, package-bound transport entry. Only fully validated data reaches first-open. */
internal object PhoneBackup {
    const val CLOUD_PATH = "phone-backup-v1/cloud"
    const val TRANSFER_PATH = "phone-backup-v1/transfer"
    const val CLOUD_LIMIT = 20L * 1024 * 1024
    const val TRANSFER_LIMIT = 140L * 1024 * 1024
    const val SETTINGS_LIMIT = 256 * 1024
    private const val MAGIC = 0x43445831 // CDX1
    private const val DIGEST_SIZE = 32

    // BackupAgent's public API 28 constants; older transports cannot assert either capability.
    fun destination(encrypted: Boolean, deviceTransfer: Boolean): String = when {
        deviceTransfer -> TRANSFER_PATH
        encrypted -> CLOUD_PATH
        else -> throw IOException("Encrypted backup transport required.")
    }

    private fun checkSize(packageId: String, settings: Int, library: Long, path: String): Long {
        val limit = when (path) {
            TRANSFER_PATH -> TRANSFER_LIMIT
            CLOUD_PATH -> CLOUD_LIMIT
            else -> throw IOException("Unknown backup destination.")
        }
        // Application IDs are ASCII. writeUTF adds a two-byte length prefix.
        val overhead = 4L + 2 + packageId.length + 4 + 8 + DIGEST_SIZE
        if (settings !in 1..SETTINGS_LIMIT || library < 0 || library > limit - overhead - settings) {
            throw IOException("Phone backup exceeds the allowed size.")
        }
        return overhead + settings + library
    }

    fun write(output: File, packageId: String, settings: ByteArray, library: File?, path: String, quota: Long) {
        val libraryBytes = library?.length() ?: 0L
        if (library != null && libraryBytes == 0L) throw IOException("Library backup is empty.")
        val size = checkSize(packageId, settings.size, libraryBytes, path)
        // Android wraps the file in a tar header and pads to a 512-byte boundary.
        if (quota >= 0 && ((size + 511) / 512 + 1) * 512 > quota) throw IOException("Backup transport quota exceeded.")
        DataOutputStream(output.outputStream().buffered()).use { out ->
            out.writeInt(MAGIC)
            out.writeUTF(packageId)
            out.writeInt(settings.size)
            out.writeLong(libraryBytes)
            val hash = MessageDigest.getInstance("SHA-256")
            val content = DigestOutputStream(out, hash)
            content.write(settings)
            if (library != null && library.inputStream().use { it.copyTo(content) } != libraryBytes) {
                throw IOException("Library backup size changed.")
            }
            out.write(hash.digest())
        }
    }

    data class Received(val settings: ByteArray, val hasLibrary: Boolean)

    // Read exactly the framework-announced entry size. Its fd can be part of a longer pipe.
    fun read(input: InputStream, size: Long, packageId: String, path: String, stagedLibrary: File): Received {
        val limit = if (path == CLOUD_PATH) CLOUD_LIMIT else TRANSFER_LIMIT
        if (size !in 1..limit) throw IOException("Invalid phone backup size.")
        var remaining = size
        val bounded = object : InputStream() {
            override fun read(): Int {
                if (remaining == 0L) return -1
                val value = input.read()
                if (value < 0) throw EOFException()
                remaining--
                return value
            }
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                if (length == 0) return 0
                if (remaining == 0L) return -1
                val count = input.read(bytes, offset, minOf(length.toLong(), remaining).toInt())
                if (count <= 0) throw EOFException()
                remaining -= count
                return count
            }
        }
        val data = DataInputStream(bounded.buffered())
        if (data.readInt() != MAGIC || data.readUTF() != packageId) throw IOException("Backup belongs to a different app or version.")
        val settingsSize = data.readInt()
        val librarySize = data.readLong()
        if (checkSize(packageId, settingsSize, librarySize, path) != size) throw IOException("Incomplete phone backup.")
        val hash = MessageDigest.getInstance("SHA-256")
        val content = DataInputStream(DigestInputStream(data, hash))
        val settings = ByteArray(settingsSize).also(content::readFully)
        if (librarySize > 0) {
            stagedLibrary.outputStream().use { out ->
                val chunk = ByteArray(64 * 1024)
                var left = librarySize
                while (left > 0) {
                    val count = minOf(chunk.size.toLong(), left).toInt()
                    content.readFully(chunk, 0, count)
                    out.write(chunk, 0, count)
                    left -= count
                }
                out.fd.sync()
            }
        }
        val digest = ByteArray(DIGEST_SIZE).also(data::readFully)
        if (!MessageDigest.isEqual(hash.digest(), digest)) throw IOException("Damaged phone backup.")
        return Received(settings, librarySize > 0)
    }
}
