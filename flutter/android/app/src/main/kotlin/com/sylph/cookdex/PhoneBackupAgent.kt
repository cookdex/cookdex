package com.sylph.cookdex

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.os.Build
import android.os.ParcelFileDescriptor
import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.util.JsonReader
import android.util.JsonToken
import androidx.annotation.Keep
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.Reader

/** Full Android backup and restore. Never traverse the app's private directory. */
@Keep
class PhoneBackupAgent : BackupAgent() {
    private external fun writeLibrary(databaseFd: Int, outputFd: Int): Boolean
    private external fun restoreLibrary(inputFd: Int, newDatabaseFd: Int): Boolean

    companion object {
        private fun restore(context: Context) = PhoneRestore(context.filesDir) { directory ->
            val fd = Os.open(directory.absolutePath, OsConstants.O_RDONLY, 0)
            try { Os.fsync(fd) } finally { Os.close(fd) }
        }

        private fun checkedSmart(importPrefs: JSONObject): Pair<String?, String?> {
            val model = if (importPrefs.has("model")) importPrefs.getString("model") else null
            if (model != null && !model.matches(Regex("[A-Za-z0-9._-]{1,120}"))) throw IOException("Invalid import model.")
            val effort = if (importPrefs.has("effort")) importPrefs.getString("effort") else null
            if (effort != null && effort !in setOf("standard", "thorough")) throw IOException("Invalid import effort.")
            return model to effort
        }

        fun finishRestore(context: Context) {
            restore(context).finish { bytes ->
                val (model, effort) = checkedSmart(JSONObject(bytes.toString(Charsets.UTF_8)))
                val edit = context.getSharedPreferences("cookdex_flutter_v1_smart", MODE_PRIVATE).edit()
                if (model != null) edit.putString("model", model)
                if (effort != null) edit.putString("effort", effort)
                if (!edit.commit()) throw IOException("Cannot restore import preferences.")
            }
        }
    }

    private val appRoot get() = File(filesDir, "flutter-v1")
    private val database get() = File(appRoot, "flutter-v1/cookdex.sqlite3")
    private val settingsFile get() = File(appRoot, "ui-preferences.json")
    private val smart get() = getSharedPreferences("cookdex_flutter_v1_smart", MODE_PRIVATE)
    private val scratch get() = File(cacheDir, "phone-backup-work-v1")
    private val stagedLibrary get() = File(scratch, "library.gz")
    private var pending: PhoneBackup.Received? = null

    // fullBackupOnly routes supported system backups through onFullBackup.
    override fun onBackup(oldState: ParcelFileDescriptor?, data: BackupDataOutput, newState: ParcelFileDescriptor) {}
    override fun onRestore(data: BackupDataInput, appVersionCode: Int, newState: ParcelFileDescriptor) {}

    override fun onCreate() {
        super.onCreate()
        if (!scratch.isDirectory && !scratch.mkdir()) throw IOException("Cannot create backup staging directory.")
        removeStaged()
    }

    private fun removeStaged() {
        pending = null
        for (file in listOf(stagedLibrary, File(filesDir, PhoneBackup.CLOUD_PATH), File(filesDir, PhoneBackup.TRANSFER_PATH))) {
            if (file.exists() && !file.delete()) throw IOException("Cannot clear backup staging.")
        }
    }

    // Skip unknown fields while streaming, including potentially large history maps.
    private fun settings(reader: Reader, root: String): JSONObject {
        var budget = PhoneBackup.SETTINGS_LIMIT
        fun account(length: Int) {
            budget -= length + 1
            if (budget < 0) throw IOException("Settings exceed the phone backup budget.")
        }
        fun readNames(input: JsonReader): JSONArray {
            input.beginArray()
            val values = JSONArray()
            while (input.hasNext()) {
                if (input.peek() != JsonToken.STRING) throw IOException("Invalid name setting.")
                val name = input.nextString()
                account(name.length)
                values.put(name)
            }
            input.endArray()
            return values
        }
        fun readObject(input: JsonReader, parent: String): JSONObject {
            val values = JSONObject()
            input.beginObject()
            while (input.hasNext()) {
                val key = input.nextName()
                val kind = PhoneSettings.kind(parent, key)
                if (kind == null || input.peek() == JsonToken.NULL) {
                    input.skipValue()
                    continue
                }
                account(key.length)
                val value: Any = when (kind) {
                    PhoneSettings.Kind.OBJECT -> readObject(input, key)
                    PhoneSettings.Kind.TEXT -> {
                        if (input.peek() != JsonToken.STRING) throw IOException("Invalid text setting.")
                        input.nextString().also { account(it.length) }
                    }
                    PhoneSettings.Kind.NUMBER -> input.nextInt()
                    PhoneSettings.Kind.BOOLEAN -> input.nextBoolean()
                    PhoneSettings.Kind.NAMES -> readNames(input)
                    PhoneSettings.Kind.NAME_GROUPS -> {
                        input.beginArray()
                        val groups = JSONArray()
                        while (input.hasNext()) {
                            account(1)
                            groups.put(readNames(input))
                        }
                        input.endArray()
                        groups
                    }
                }
                values.put(key, value)
            }
            input.endObject()
            return values
        }
        return JsonReader(reader).use { input ->
            val result = readObject(input, root)
            if (input.peek() != JsonToken.END_DOCUMENT) throw IOException("Invalid settings file.")
            result
        }
    }

    private fun exportSettings(): ByteArray {
        val ui = if (settingsFile.isFile) settings(settingsFile.reader(Charsets.UTF_8), "ui") else JSONObject()
        val importPrefs = JSONObject()
        for (key in listOf("model", "effort")) {
            smart.getString(key, null)?.let { importPrefs.put(key, it) }
        }
        return JSONObject().put("ui", ui).put("smart", importPrefs).toString().toByteArray(Charsets.UTF_8)
    }

    override fun onFullBackup(data: FullBackupDataOutput) {
        if (Build.VERSION.SDK_INT < 28) throw IOException("Cannot verify backup transport protection.")
        if (File(filesDir, "phone-restore-pending-v1").exists()) throw IOException("Library restore is still pending.")
        val flags = data.transportFlags
        if (flags and FLAG_CROSS_PLATFORM_DATA_TRANSFER_IOS != 0) throw IOException("Unsupported restore platform.")
        val path = PhoneBackup.destination(
            flags and FLAG_CLIENT_SIDE_ENCRYPTION_ENABLED != 0,
            flags and FLAG_DEVICE_TO_DEVICE_TRANSFER != 0,
        )
        removeStaged()
        val transportFile = File(filesDir, path)
        try {
            val preferences = exportSettings()
            val library = if (database.isFile) {
                System.loadLibrary("cookdex_bridge")
                ParcelFileDescriptor.open(database, ParcelFileDescriptor.MODE_READ_ONLY).use { db ->
                    ParcelFileDescriptor.open(stagedLibrary, ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE or ParcelFileDescriptor.MODE_WRITE_ONLY).use { out ->
                        if (!writeLibrary(db.fd, out.fd)) throw IOException("Cannot prepare phone library.")
                    }
                }
                stagedLibrary
            } else {
                null
            }
            val parent = transportFile.parentFile!!
            if (!parent.isDirectory && !parent.mkdir()) throw IOException("Cannot stage phone backup.")
            PhoneBackup.write(transportFile, packageName, preferences, library, path, data.quota)
            fullBackupFile(transportFile, data)
        } finally {
            removeStaged()
        }
    }

    override fun onRestoreFile(data: ParcelFileDescriptor, size: Long, destination: File, type: Int, mode: Long, mtime: Long) {
        if (type == TYPE_DIRECTORY && size == 0L) return
        val path = listOf(PhoneBackup.CLOUD_PATH, PhoneBackup.TRANSFER_PATH)
            .singleOrNull { File(filesDir, it).canonicalFile == destination.canonicalFile }
        if (type != TYPE_FILE || path == null || pending != null) {
            removeStaged()
            throw IOException("Unexpected phone backup entry.")
        }
        try {
            // Own the duplicate. The framework retains its original pipe fd.
            ParcelFileDescriptor.AutoCloseInputStream(ParcelFileDescriptor.dup(data.fileDescriptor)).use { input ->
                pending = PhoneBackup.read(input, size, packageName, path, stagedLibrary)
            }
        } catch (error: Exception) {
            removeStaged()
            throw error
        }
    }

    override fun onRestoreFinished() {
        val received = pending ?: return
        try {
            if (database.exists()) return
            val restored = settings(received.settings.inputStream().reader(Charsets.UTF_8), "settings")
            val ui = restored.getJSONObject("ui").toString().toByteArray(Charsets.UTF_8)
            val smartSettings = restored.getJSONObject("smart")
            checkedSmart(smartSettings)
            val build: ((File) -> Boolean)? = if (received.hasLibrary) { newDb ->
                System.loadLibrary("cookdex_bridge")
                ParcelFileDescriptor.open(stagedLibrary, ParcelFileDescriptor.MODE_READ_ONLY).use { input ->
                    ParcelFileDescriptor.open(newDb, ParcelFileDescriptor.MODE_READ_WRITE).use { output ->
                        restoreLibrary(input.fd, output.fd)
                    }
                }
            } else null
            restore(this).prepare(ui, smartSettings.toString().toByteArray(Charsets.UTF_8), build)
        } finally {
            removeStaged()
        }
    }
}
