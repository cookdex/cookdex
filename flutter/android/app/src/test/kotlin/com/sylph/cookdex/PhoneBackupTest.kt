package com.sylph.cookdex

import java.io.*
import java.nio.file.Files
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

class PhoneBackupTest {
    private val id = "com.sylph.cookdex.dev"
    private val preferences = """{"ui":{"themeMode":"dark"},"smart":{"model":"gemini-3.8-flash"}}""".toByteArray()
    private fun withFolder(action: (File) -> Unit) {
        val folder = Files.createTempDirectory("cookdex-backup-test").toFile()
        try { action(folder) } finally { folder.deleteRecursively() }
    }

    @Test fun encryptionAndTransferCapabilitiesAreIndependent() {
        assertThrows(IOException::class.java) { PhoneBackup.destination(false, false) }
        assertEquals(PhoneBackup.CLOUD_PATH, PhoneBackup.destination(true, false))
        assertEquals(PhoneBackup.TRANSFER_PATH, PhoneBackup.destination(false, true))
        assertEquals(PhoneBackup.TRANSFER_PATH, PhoneBackup.destination(true, true))
    }

    @Test fun restoreBindsToApplicationIdAndConsumesOneCompleteEntry() = withFolder { dir ->
        val lib = File(dir, "source").apply { writeBytes(ByteArray(120000) { (it % 211).toByte() }) }
        val archive = File(dir, "archive")
        val target = File(dir, "staging")
        PhoneBackup.write(archive, id, preferences, lib, PhoneBackup.CLOUD_PATH, 24L shl 20)
        val bytes = archive.readBytes()
        val input = ByteArrayInputStream(bytes + byteArrayOf(7, 8, 9))
        val decoded = PhoneBackup.read(input, bytes.size.toLong(), id, PhoneBackup.CLOUD_PATH, target)
        assertTrue(decoded.hasLibrary)
        assertArrayEquals(preferences, decoded.settings)
        assertArrayEquals(lib.readBytes(), target.readBytes())
        assertEquals(7, input.read())
        fun reject(payload: ByteArray, packageName: String = id, length: Long = payload.size.toLong()) {
            assertThrows(IOException::class.java) {
                PhoneBackup.read(payload.inputStream(), length, packageName, PhoneBackup.CLOUD_PATH, target)
            }
        }
        reject(bytes, "com.sylph.cookdex")
        reject(bytes, "com.sylph.cookdex.dev.profile")
        reject(bytes.copyOf(bytes.size - 10))
        reject(bytes.copyOf(bytes.size - 10), length = bytes.size.toLong())
        reject(bytes.copyOf().apply { this[lastIndex - 85] = (this[lastIndex - 85] + 1).toByte() })
    }

    @Test fun emptyInstallationHasASettingsOnlyBackup() = withFolder { dir ->
        val archive = File(dir, "archive")
        val staged = File(dir, "library")
        PhoneBackup.write(archive, id, preferences, null, PhoneBackup.TRANSFER_PATH, Long.MAX_VALUE)
        val decoded = archive.inputStream().use {
            PhoneBackup.read(it, archive.length(), id, PhoneBackup.TRANSFER_PATH, staged)
        }
        assertArrayEquals(preferences, decoded.settings)
        assertFalse(decoded.hasLibrary)
        assertFalse(staged.exists())
    }

    @Test fun cloudQuotaIncludesSettingsAndTransportQuotaIsCheckedBeforeWriting() = withFolder { dir ->
        val source = File(dir, "library").apply { RandomAccessFile(this, "rw").use { it.setLength(PhoneBackup.CLOUD_LIMIT) } }
        val archive = File(dir, "archive")
        fun reject(path: String, quota: Long, settings: ByteArray = preferences) {
            assertThrows(IOException::class.java) { PhoneBackup.write(archive, id, settings, source, path, quota) }
            assertFalse(archive.exists())
        }
        reject(PhoneBackup.CLOUD_PATH, Long.MAX_VALUE)
        reject(PhoneBackup.TRANSFER_PATH, 4096)
        reject(PhoneBackup.TRANSFER_PATH, Long.MAX_VALUE, ByteArray(PhoneBackup.SETTINGS_LIMIT + 1))
        PhoneBackup.write(archive, id, preferences, source, PhoneBackup.TRANSFER_PATH, Long.MAX_VALUE)
        assertTrue(archive.length() > PhoneBackup.CLOUD_LIMIT)
    }

    @Test fun invalidNativeLibraryNeverInstallsSettingsOrHidesExistingData() = withFolder { files ->
        val live = File(files, "flutter-v1").apply { mkdir() }
        val ui = File(live, "ui-preferences.json").apply { writeText("original") }
        val restore = PhoneRestore(files) {}
        assertThrows(IOException::class.java) {
            restore.prepare("incoming".toByteArray(), preferences) { db ->
                db.writeText("partial SQLite")
                false
            }
        }
        restore.finish { fail("Settings reached the live app") }
        assertEquals("original", ui.readText())
        assertFalse(File(live, "flutter-v1/cookdex.sqlite3").exists())
        assertFalse(File(files, "phone-restore-pending-v1").exists())
    }

    @Test fun interruptedRootPromotionAndSmartCommitRecoverBeforeOpening() = withFolder { files ->
        val live = File(files, "flutter-v1").apply { mkdir() }
        File(live, "ui-preferences.json").writeText("old")
        val restore = PhoneRestore(files) {}
        assertTrue(restore.prepare("new".toByteArray(), preferences) { db ->
            db.writeText("validated SQLite")
            true
        })
        val pending = File(files, "phone-restore-pending-v1")
        // Simulate a restart after moving the previous root aside.
        assertTrue(live.renameTo(File(pending, "previous")))
        assertThrows(IOException::class.java) {
            PhoneRestore(files) {}.finish { throw IOException("simulated interrupted preferences write") }
        }
        assertEquals("new", File(live, "ui-preferences.json").readText())
        assertEquals("validated SQLite", File(live, "flutter-v1/cookdex.sqlite3").readText())
        assertTrue(pending.exists())
        var commits = 0
        PhoneRestore(files) {}.finish {
            assertArrayEquals(preferences, it)
            commits++
        }
        assertFalse(pending.exists())
        PhoneRestore(files) {}.finish { commits++ }
        assertEquals(1, commits)
    }

    @Test fun unrelatedLiveLibraryWinsEvenIfItAppearsAfterStaging() = withFolder { files ->
        val restore = PhoneRestore(files) {}
        assertTrue(restore.prepare("new".toByteArray(), preferences) { db -> db.writeText("staged"); true })
        val database = File(files, "flutter-v1/flutter-v1/cookdex.sqlite3")
        database.parentFile!!.mkdirs()
        database.writeText("existing library")
        restore.finish { fail("Unrelated library must retain its own preferences") }
        assertEquals("existing library", database.readText())
        assertFalse(restore.prepare("new".toByteArray(), preferences) { fail("Already initialized"); false })
    }

    @Test fun settingsFilterDeniesUnknownPrivateAndTransientValuesAtEveryLevel() {
        val forbidden = listOf("key", "encryptedKey", "secret", "peer", "pairing", "query", "recentRecipeOffsets",
            "scrollOffset", "beforeSearch", "steps", "checks", "lastUpdateCheckMs", "draft", "lastImport", "snapshots")
        for (scope in listOf("settings", "ui", "smartCreate", "keptSeparate", "retiredModels", "smart")) {
            for (key in forbidden) assertNull("Unexpected $scope/$key", PhoneSettings.kind(scope, key))
        }
        for (key in listOf("view", "themeMode", "recipeTextSize", "keptSeparate", "smartCreate", "youtubeWatchModel")) {
            assertNotNull(PhoneSettings.kind("ui", key))
        }
        for (key in listOf("avoid", "staples", "otherPreferences", "servings", "extraIngredients",
                "photoModel","ideaModel","recipeModel","photoThinking","ideaThinking","recipeThinking")) {
            assertNotNull(PhoneSettings.kind("smartCreate", key))
        }
        assertNotNull(PhoneSettings.kind("smart", "model"))
        assertNotNull(PhoneSettings.kind("smart", "effort"))
        assertNull(PhoneSettings.kind("smart", "hasKey"))
    }

    @Test fun manifestAndBothRuleFormatsOnlyOptInOurStagedArtifacts() {
        val main = listOf(File("src/main"), File("app/src/main"), File("flutter/android/app/src/main")).first { File(it, "AndroidManifest.xml").isFile }
        fun xml(relative: String) = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(File(main, relative))
        val app = xml("AndroidManifest.xml").getElementsByTagName("application").item(0) as Element
        assertEquals("true", app.getAttribute("android:allowBackup"))
        assertEquals("true", app.getAttribute("android:fullBackupOnly"))
        assertEquals("com.sylph.cookdex.PhoneBackupAgent", app.getAttribute("android:backupAgent"))
        val modern = xml("res/xml/data_extraction_rules.xml")
        val legacy = xml("res/xml/backup_rules.xml")
        val names = setOf(PhoneBackup.CLOUD_PATH, PhoneBackup.TRANSFER_PATH)
        for (rules in listOf(modern, legacy)) {
            val includes = rules.getElementsByTagName("include")
            assertEquals(2, includes.length)
            val paths = (0 until includes.length).map {
                val node = includes.item(it) as Element
                assertEquals("file", node.getAttribute("domain"))
                node.getAttribute("path")
            }
            assertEquals(names, paths.toSet())
        }
        val cloud = modern.getElementsByTagName("cloud-backup").item(0) as Element
        assertEquals("true", cloud.getAttribute("disableIfNoEncryptionCapabilities"))
        assertEquals(PhoneBackup.CLOUD_PATH, (cloud.getElementsByTagName("include").item(0) as Element).getAttribute("path"))
        val requirements = legacy.getElementsByTagName("include")
        for (i in 0 until requirements.length) {
            val node = requirements.item(i) as Element
            assertEquals(if (node.getAttribute("path") == PhoneBackup.CLOUD_PATH) "clientSideEncryption" else "deviceToDeviceTransfer", node.getAttribute("requireFlags"))
        }
    }
}
