package com.sylph.cookdex

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.net.Uri
import android.provider.MediaStore
import android.test.ActivityInstrumentationTestCase2
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Run only on the disposable C7 emulator. Uses generated raster/text fixtures. */
@Suppress("DEPRECATION")
class ImportHostTest : ActivityInstrumentationTestCase2<MainActivity>(MainActivity::class.java) {
    override fun setUp() { super.setUp(); activity; instrumentation.waitForIdleSync() }
    private fun host(): ImportHost = MainActivity::class.java.getDeclaredField("importHost").let { it.isAccessible = true; it.get(activity) as ImportHost }
    private class Reply : MethodChannel.Result {
        val latch = CountDownLatch(1); var value: Any? = null; var error: String? = null
        override fun success(result: Any?) { value = result; latch.countDown() }
        override fun error(code: String, message: String?, details: Any?) { error = message; latch.countDown() }
        override fun notImplemented() { error = "Not implemented"; latch.countDown() }
        fun await(): Any? { check(latch.await(15, TimeUnit.SECONDS)); check(error == null) { error!! }; return value }
    }
    private fun jpeg(width: Int = 2400, height: Int = 1200): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.GREEN)
        return try { ByteArrayOutputStream().use { output -> bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output); output.toByteArray() } } finally { bitmap.recycle() }
    }
    fun testImageOrientationResizeAndExifRemoval() {
        val original = File(activity.cacheDir, "c7-synthetic-orientation.jpg")
        try {
            original.writeBytes(jpeg())
            ExifInterface(original.absolutePath).apply {
                setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
                setAttribute(ExifInterface.TAG_GPS_LATITUDE, "10/1,0/1,0/1")
                setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
                saveAttributes()
            }
            val method = ImportHost::class.java.getDeclaredMethod("preparePhoto", ByteArray::class.java).apply { isAccessible = true }
            val prepared = method.invoke(host(), original.readBytes()) as ByteArray
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(prepared, 0, prepared.size, bounds)
            assertEquals(1000, bounds.outWidth); assertEquals(2000, bounds.outHeight)
            val exif = ExifInterface(ByteArrayInputStream(prepared))
            assertNull(exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
            // Android returns synthetic orientation 0 when no EXIF block exists.
            assertEquals(ExifInterface.ORIENTATION_UNDEFINED, exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED))
            assertFalse(String(prepared, Charsets.ISO_8859_1).contains("Exif\u0000\u0000"))
            assertTrue(prepared[0] == 0xff.toByte() && prepared[1] == 0xd8.toByte())
        } finally { original.delete() }
    }
    fun testTextPickerResultAndCancellation() {
        val fixture = File(activity.cacheDir, "c7-synthetic.txt").apply { writeText("Cream\nIngredients:\n0.33 cup cream\nSteps:\nMix.") }
        try {
            val monitor = instrumentation.addMonitor(IntentFilter(Intent.ACTION_OPEN_DOCUMENT).apply { addDataType("*/*"); addCategory(Intent.CATEGORY_OPENABLE) }, Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(Uri.fromFile(fixture))), true)
            val reply = Reply()
            instrumentation.runOnMainSync { host().handle(MethodCall("pickText", null), reply) }
            assertTrue((reply.await() as String).contains("0.33 cup cream"))
            instrumentation.removeMonitor(monitor)
            val cancelMonitor = instrumentation.addMonitor(IntentFilter(Intent.ACTION_OPEN_DOCUMENT).apply { addDataType("*/*"); addCategory(Intent.CATEGORY_OPENABLE) }, Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null), true)
            val cancelled = Reply()
            instrumentation.runOnMainSync { host().handle(MethodCall("pickText", null), cancelled) }
            assertNull(cancelled.await())
            instrumentation.removeMonitor(cancelMonitor)
        } finally { fixture.delete() }
    }
    fun testGalleryPartialReadRetainsValidPhoto() {
        val fixture = File(activity.cacheDir, "c7-synthetic.jpg").apply { writeBytes(jpeg(200, 100)) }
        try {
            val data = Intent().apply {
                clipData = android.content.ClipData.newRawUri("synthetic", Uri.fromFile(fixture)).apply {
                    addItem(android.content.ClipData.Item(Uri.fromFile(File(activity.cacheDir, "missing-c7-photo.jpg"))))
                }
            }
            val monitor = instrumentation.addMonitor(IntentFilter(Intent.ACTION_OPEN_DOCUMENT).apply { addDataType("*/*"); addCategory(Intent.CATEGORY_OPENABLE) }, Instrumentation.ActivityResult(Activity.RESULT_OK, data), true)
            val reply = Reply()
            instrumentation.runOnMainSync { host().handle(MethodCall("pickPhotos", mapOf("camera" to false, "maxCount" to 8)), reply) }
            val result = reply.await() as Map<*, *>
            assertEquals(1, (result["photos"] as List<*>).size); assertEquals(1, (result["errors"] as List<*>).size)
            instrumentation.removeMonitor(monitor)
        } finally { fixture.delete() }
    }
    fun testCameraCaptureCancellationCleansTemporaryFile() {
        val monitor = instrumentation.addMonitor(IntentFilter(MediaStore.ACTION_IMAGE_CAPTURE), Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null), true)
        val reply = Reply()
        instrumentation.runOnMainSync { host().handle(MethodCall("pickPhotos", mapOf("camera" to true, "maxCount" to 1)), reply) }
        assertNull(reply.await())
        assertEquals(0, File(activity.cacheDir, "import-camera").listFiles()?.size ?: 0)
        instrumentation.removeMonitor(monitor)
    }
    fun testCameraSuccessUsesFullResolutionOutputAndCleansCapture() {
        val fixture = jpeg(200, 100)
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != MediaStore.ACTION_IMAGE_CAPTURE) return null
                @Suppress("DEPRECATION")
                val uri = intent.getParcelableExtra<Uri>(MediaStore.EXTRA_OUTPUT)!!
                activity.contentResolver.openOutputStream(uri)!!.use { it.write(fixture) }
                return Instrumentation.ActivityResult(Activity.RESULT_OK, null)
            }
        }
        instrumentation.addMonitor(monitor)
        val reply = Reply()
        instrumentation.runOnMainSync { host().handle(MethodCall("pickPhotos", mapOf("camera" to true, "maxCount" to 1)), reply) }
        val result = reply.await() as Map<*, *>
        assertEquals(1, (result["photos"] as List<*>).size)
        assertEquals(0, (result["errors"] as List<*>).size)
        assertEquals(0, File(activity.cacheDir, "import-camera").listFiles()?.size ?: 0)
        instrumentation.removeMonitor(monitor)
    }
    fun testOversizedOriginalAndDecodedBoundsRejectBeforeRasterAllocation() {
        val bytes = jpeg(200, 100)
        var frame = -1
        for (i in 0 until bytes.size - 8) {
            if (bytes[i] == 0xff.toByte() && bytes[i + 1] in listOf(0xc0.toByte(), 0xc2.toByte())) { frame = i; break }
        }
        assertTrue(frame >= 0)
        bytes[frame + 5] = 0x27; bytes[frame + 6] = 0x10
        bytes[frame + 7] = 0x27; bytes[frame + 8] = 0x10
        val prepare = ImportHost::class.java.getDeclaredMethod("preparePhoto", ByteArray::class.java).apply { isAccessible = true }
        try { prepare.invoke(host(), bytes); fail("100 MP header accepted") }
        catch (error: java.lang.reflect.InvocationTargetException) { assertTrue(error.cause is IllegalArgumentException) }
        val fixture = File(activity.cacheDir, "c7-synthetic-too-large.jpg")
        try {
            java.io.RandomAccessFile(fixture, "rw").use { it.setLength(25L * 1024 * 1024 + 1) }
            val monitor = instrumentation.addMonitor(IntentFilter(Intent.ACTION_OPEN_DOCUMENT).apply { addDataType("*/*"); addCategory(Intent.CATEGORY_OPENABLE) }, Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(Uri.fromFile(fixture))), true)
            val reply = Reply()
            instrumentation.runOnMainSync { host().handle(MethodCall("pickPhotos", mapOf("camera" to false, "maxCount" to 8)), reply) }
            val result = reply.await() as Map<*, *>
            assertEquals(0, (result["photos"] as List<*>).size)
            assertEquals(1, (result["errors"] as List<*>).size)
            instrumentation.removeMonitor(monitor)
        } finally { fixture.delete() }
    }
}
