package com.sylph.cookdex

import java.io.File
import java.io.IOException
import java.util.UUID

/** A verified SQLite library and its UI settings move into place with one rename.
 * The pending marker survives process death until smart preferences are committed. */
internal class PhoneRestore(private val files: File, private val syncDirectory: (File) -> Unit) {
    private val live = File(files, "flutter-v1")
    private val database = "flutter-v1/cookdex.sqlite3"
    private val pending = File(files, "phone-restore-pending-v1")
    private val work = File(files, "phone-restore-work-v1")
    private val done = File(files, "phone-restore-completed-v1")
    private val owner = ".phone-restore-owner"

    private fun durable(file: File, bytes: ByteArray) {
        file.outputStream().use { out -> out.write(bytes); out.fd.sync() }
    }
    private fun rename(from: File, to: File) {
        if (!from.renameTo(to)) throw IOException("Cannot install restored phone data.")
        syncDirectory(to.parentFile!!)
        if (from.parentFile != to.parentFile) syncDirectory(from.parentFile!!)
    }
    private fun retire() {
        if (done.exists() && !done.deleteRecursively()) throw IOException("Cannot retire completed restore.")
        rename(pending, done)
        done.deleteRecursively()
    }

    fun prepare(ui: ByteArray, smart: ByteArray, buildDatabase: ((File) -> Boolean)?): Boolean {
        if (File(live, database).exists() || pending.exists()) return false
        if (work.exists() && !work.deleteRecursively()) throw IOException("Cannot clear incomplete restore.")
        val candidate = File(work, "root")
        if (!candidate.mkdirs()) throw IOException("Cannot stage phone restore.")
        try {
            if (buildDatabase != null) {
                val db = File(candidate, database)
                if (!db.parentFile!!.mkdir() || !db.createNewFile()) throw IOException("Cannot stage phone library.")
                // Native code opens this new database, validates the compressed
                // history and commits it before the candidate can be published.
                if (!buildDatabase(db)) throw IOException("Phone library failed validation.")
                if (db.length() == 0L) throw IOException("Restored library is empty.")
                db.outputStreamForSync()
                syncDirectory(db.parentFile!!)
            }
            val token = UUID.randomUUID().toString().toByteArray(Charsets.UTF_8)
            durable(File(candidate, owner), token)
            durable(File(candidate, "ui-preferences.json"), ui)
            durable(File(work, "token"), token)
            durable(File(work, "smart.json"), smart)
            syncDirectory(candidate)
            syncDirectory(work)
            rename(work, pending)
            return true
        } finally {
            if (work.exists()) work.deleteRecursively()
        }
    }

    // Called before Dart gets the private root or opens any preferences/database.
    fun finish(commitSmart: (ByteArray) -> Unit) {
        if (done.exists()) done.deleteRecursively()
        if (!pending.exists()) return
        val token = File(pending, "token").readText()
        val installedMarker = File(live, owner)
        val alreadyInstalled = installedMarker.isFile && installedMarker.readText() == token
        if (!alreadyInstalled) {
            if (File(live, database).exists()) {
                retire()
                return
            }
            val candidate = File(pending, "root")
            if (!candidate.isDirectory || File(candidate, owner).readText() != token) {
                throw IOException("Incomplete staged phone restore.")
            }
            // An interrupted promotion may already have moved this directory aside.
            // Preserve it until both stores are committed.
            if (live.exists()) rename(live, File(pending, "previous"))
            rename(candidate, live)
        }
        commitSmart(File(pending, "smart.json").readBytes())
        retire()
        installedMarker.delete()
    }

    private fun File.outputStreamForSync() = java.io.RandomAccessFile(this, "rw").use { it.fd.sync() }
}
