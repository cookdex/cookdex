package com.sylph.cookdex

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.test.ActivityInstrumentationTestCase2
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Disposable C8 emulator only. Never starts a real share target or writes outside cache. */
@Suppress("DEPRECATION")
class ExportHostTest : ActivityInstrumentationTestCase2<MainActivity>(MainActivity::class.java) {
    override fun setUp() { super.setUp(); activity; instrumentation.waitForIdleSync() }

    private fun host(): ExportHost = MainActivity::class.java.getDeclaredField("exportHost").let {
        it.isAccessible = true; it.get(activity) as ExportHost
    }

    private class Reply : MethodChannel.Result {
        val latch = CountDownLatch(1)
        val calls = AtomicInteger(0)
        var value: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        override fun success(result: Any?) { value = result; calls.incrementAndGet(); latch.countDown() }
        override fun error(code: String, message: String?, details: Any?) {
            errorCode = code; errorMessage = message; calls.incrementAndGet(); latch.countDown()
        }
        override fun notImplemented() { errorCode = "notImplemented"; calls.incrementAndGet(); latch.countDown() }
        fun await(): Any? {
            check(latch.await(15, TimeUnit.SECONDS)) { "Export callback timed out" }
            check(errorCode == null) { "$errorCode: $errorMessage" }
            check(calls.get() == 1) { "Export completed more than once" }
            return value
        }
        fun awaitError(): String? {
            check(latch.await(15, TimeUnit.SECONDS)) { "Export error callback timed out" }
            check(calls.get() == 1) { "Export completed more than once" }
            return errorCode
        }
    }

    private fun pickerMonitor(resultCode: Int, uri: Uri? = null): Instrumentation.ActivityMonitor =
        instrumentation.addMonitor(
            IntentFilter(Intent.ACTION_CREATE_DOCUMENT).apply {
                addDataType("*/*"); addCategory(Intent.CATEGORY_OPENABLE)
            },
            Instrumentation.ActivityResult(resultCode, uri?.let { Intent().setData(it) }),
            true,
        )

    fun testMessageSharingSuppliesExactTextWithoutFileAttachment() {
        val text = "Synthetic crème soup\nIngredients:\n- 33/100 cup cream\nSteps:\n1. Mix."
        var chooser: Intent? = null
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_CHOOSER) return null
                chooser = Intent(intent)
                return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            val reply = Reply()
            instrumentation.runOnMainSync {
                host().handle(MethodCall("shareText", mapOf("text" to text, "title" to "Synthetic crème soup")), reply)
            }
            assertEquals("opened", reply.await())
            val send = chooser?.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                ?: throw AssertionError("System chooser did not receive a SEND intent")
            assertEquals(Intent.ACTION_SEND, send.action)
            assertEquals("text/plain", send.type)
            assertEquals(text, send.getStringExtra(Intent.EXTRA_TEXT))
            assertEquals("Synthetic crème soup", send.getStringExtra(Intent.EXTRA_SUBJECT))
            assertFalse(send.hasExtra(Intent.EXTRA_STREAM))
            assertNull(send.clipData)
        } finally { instrumentation.removeMonitor(monitor) }
    }

    fun testFileSharingGrantsReadUriAndContainsExactUtf8Bytes() {
        val filename = "c8-synthetic-${UUID.randomUUID()}.txt"
        val text = "Synthetic lemon soup\n- 33/100 cup crème\n1. Mix 🍋.\n"
        var chooser: Intent? = null
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_CHOOSER) return null
                chooser = Intent(intent)
                return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            val reply = Reply()
            instrumentation.runOnMainSync {
                host().handle(MethodCall("shareFile", mapOf("text" to text, "filename" to filename)), reply)
            }
            assertEquals("opened", reply.await())
            val selected = chooser ?: throw AssertionError("System chooser was not opened")
            val send = selected.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                ?: throw AssertionError("System chooser did not receive a SEND intent")
            val uri = send.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                ?: throw AssertionError("Shared file URI is missing")
            assertEquals(Intent.ACTION_SEND, send.action)
            assertEquals("text/plain", send.type)
            assertEquals("content", uri.scheme)
            assertEquals("${activity.packageName}.import-files", uri.authority)
            assertEquals(filename, uri.lastPathSegment)
            assertTrue(uri.path?.startsWith("/export-text/") == true)
            assertTrue(send.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
            assertTrue(selected.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
            assertEquals(0, send.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            assertEquals(uri, send.clipData?.getItemAt(0)?.uri)
            assertFalse(send.hasExtra(Intent.EXTRA_TEXT))
            val actual = activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw AssertionError("Prepared shared file cannot be read")
            assertTrue(text.toByteArray(Charsets.UTF_8).contentEquals(actual))
        } finally {
            instrumentation.removeMonitor(monitor)
            // Remove this generated fixture only, retaining any other cache entries.
            File(activity.cacheDir, "export-text").listFiles()?.forEach { directory ->
                val fixture = File(directory, filename)
                if (fixture.exists()) { fixture.delete(); directory.delete() }
            }
        }
    }

    fun testSaveCancelledReturnsCancelledAndLeavesFixtureUntouched() {
        val fixture = File(activity.cacheDir, "c8-save-cancel-${UUID.randomUUID()}.txt").apply {
            writeText("Original synthetic contents")
        }
        val monitor = pickerMonitor(Activity.RESULT_CANCELED, Uri.fromFile(fixture))
        try {
            val reply = Reply()
            instrumentation.runOnMainSync {
                host().handle(MethodCall("saveText", mapOf("text" to "Replacement", "filename" to "recipe.txt")), reply)
            }
            assertEquals("cancelled", reply.await())
            assertEquals("Original synthetic contents", fixture.readText())
            assertEquals(1, reply.calls.get())
        } finally { instrumentation.removeMonitor(monitor); fixture.delete() }
    }

    fun testSaveReportsSuccessOnlyAfterCompleteUtf8WriteAndTruncation() {
        val text = "Synthetic crème soup\n- 33/100 cup cream\n1. Mix 🍋.\n"
        val fixture = File(activity.cacheDir, "c8-save-output-${UUID.randomUUID()}.txt").apply {
            writeText("OLD TRAILING DATA ".repeat(200))
        }
        val monitor = pickerMonitor(Activity.RESULT_OK, Uri.fromFile(fixture))
        try {
            val reply = Reply()
            instrumentation.runOnMainSync {
                host().handle(MethodCall("saveText", mapOf("text" to text, "filename" to "recipe.txt")), reply)
            }
            assertEquals("saved", reply.await())
            assertTrue(text.toByteArray(Charsets.UTF_8).contentEquals(fixture.readBytes()))
            assertEquals(text.toByteArray(Charsets.UTF_8).size.toLong(), fixture.length())
            assertEquals(1, reply.calls.get())
        } finally { instrumentation.removeMonitor(monitor); fixture.delete() }
    }

    fun testSaveDoesNotCompleteBeforeDestinationResultAndRejectsConcurrentPicker() {
        // Use an isolated host so the blocked picker's automatic Activity result
        // goes to MainActivity's host; manually deliver this host's result below.
        val isolated = ExportHost(activity)
        val monitor = pickerMonitor(Activity.RESULT_CANCELED)
        try {
            val first = Reply()
            val second = Reply()
            instrumentation.runOnMainSync {
                isolated.handle(MethodCall("saveText", mapOf("text" to "First", "filename" to "first.txt")), first)
                isolated.handle(MethodCall("saveText", mapOf("text" to "Second", "filename" to "second.txt")), second)
            }
            instrumentation.waitForIdleSync()
            assertEquals(0, first.calls.get())
            assertEquals(1L, first.latch.count)
            assertEquals("busy", second.awaitError())
            assertNull(second.value)
            instrumentation.runOnMainSync {
                assertTrue(isolated.onActivityResult(ExportHost.SAVE_TEXT, Activity.RESULT_CANCELED, null))
            }
            assertEquals("cancelled", first.await())
        } finally {
            instrumentation.removeMonitor(monitor)
            instrumentation.runOnMainSync { isolated.close() }
        }
    }

    fun testUnwritableDestinationReportsErrorInsteadOfSaved() {
        val monitor = pickerMonitor(Activity.RESULT_OK, Uri.parse("content://invalid.cookdex.synthetic/no-output"))
        try {
            val reply = Reply()
            instrumentation.runOnMainSync {
                host().handle(MethodCall("saveText", mapOf("text" to "Synthetic text", "filename" to "recipe.txt")), reply)
            }
            assertEquals("save", reply.awaitError())
            assertNull(reply.value)
        } finally { instrumentation.removeMonitor(monitor) }
        // A failed write releases the picker for a later, explicit retry.
        val retryMonitor = pickerMonitor(Activity.RESULT_CANCELED)
        try {
            val retry = Reply()
            instrumentation.runOnMainSync {
                host().handle(MethodCall("saveText", mapOf("text" to "Synthetic retry", "filename" to "recipe.txt")), retry)
            }
            assertEquals("cancelled", retry.await())
        } finally { instrumentation.removeMonitor(retryMonitor) }
    }

    fun testOversizedMessageAndUnsafeFilenameFailBeforeOpeningNativeUi() {
        val message = Reply()
        val filename = Reply()
        val opened = AtomicInteger(0)
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_CHOOSER) return null
                opened.incrementAndGet()
                return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            instrumentation.runOnMainSync {
                host().handle(MethodCall("shareText", mapOf("text" to "x".repeat(256 * 1024 + 1), "title" to "Synthetic")), message)
                host().handle(MethodCall("shareFile", mapOf("text" to "Synthetic", "filename" to "../outside.txt")), filename)
            }
            assertEquals("limit", message.awaitError())
            assertNull(message.value)
            assertEquals("filename", filename.awaitError())
            assertNull(filename.value)
            assertEquals(0, opened.get())
        } finally { instrumentation.removeMonitor(monitor) }
    }
}
