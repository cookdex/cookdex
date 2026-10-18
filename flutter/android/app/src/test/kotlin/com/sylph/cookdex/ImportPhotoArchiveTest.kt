package com.sylph.cookdex

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class ImportPhotoArchiveTest {
    private fun fixture(action: (ImportPhotoArchive, File) -> Unit) {
        val root = Files.createTempDirectory("cookdex-photo-test").toFile()
        try {
            val capture = File(root, "capture.jpg").apply { writeBytes(byteArrayOf(1, 2, 3, 4, 5)) }
            action(ImportPhotoArchive(File(root, "originals")), capture)
        } finally { root.deleteRecursively() }
    }
    @Test fun onlySavePublishesOriginalBytesInOrder() = fixture { archive, capture ->
        val first = archive.retain(capture)
        val second = archive.retain(capture)
        val output = mutableListOf<String>()
        assertTrue(archive.save(listOf(first, second), "Mom's Taco Meat") { file, name ->
            assertArrayEquals(capture.readBytes(), file.readBytes())
            output.add(name)
        }.isEmpty())
        assertEquals(listOf("Mom's Taco Meat - card 1.jpg", "Mom's Taco Meat - card 2.jpg"), output)
        assertEquals(listOf(1), archive.save(listOf(first), "Again") { _, _ -> fail() })
    }
    @Test fun discardAndNextLaunchCleanupNeverPublish() = fixture { archive, capture ->
        val removed = archive.retain(capture)
        archive.discard(listOf(removed, "../capture.jpg"))
        assertTrue(capture.exists())
        assertEquals(listOf(1), archive.save(listOf(removed), "Discard") { _, _ -> fail() })
        val abandoned = archive.retain(capture)
        archive.clear()
        assertEquals(listOf(1), archive.save(listOf(abandoned), "Abandoned") { _, _ -> fail() })
    }
    @Test fun failureDoesNotConsumeOtherOriginalsOrPublishTwice() = fixture { archive, capture ->
        val id = archive.retain(capture)
        assertEquals(listOf(1), archive.save(listOf(id), "Retry") { _, _ -> error("synthetic failure") })
        assertTrue(archive.save(listOf(id), "Retry") { file, _ -> assertTrue(file.exists()) }.isEmpty())
    }
    @Test fun galleryCopiesPreserveJpegBytesAndNeverModifyTheSource() = fixture { archive, source ->
        val bytes = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte()) + ByteArray(300_000) { (it % 251).toByte() }
        source.writeBytes(bytes)
        val copy = archive.retainPhoto(source.readBytes()) { error("JPEG must not be re-encoded") }
        assertTrue(archive.save(listOf(copy), "Gallery") { file, name ->
            assertArrayEquals(bytes, file.readBytes())
            assertEquals("Gallery - card 1.jpg", name)
        }.isEmpty())
        assertArrayEquals(bytes, source.readBytes())
        val discarded = archive.retainPhoto(source.readBytes()) { error("JPEG must not be re-encoded") }
        archive.discard(listOf(discarded))
        assertArrayEquals(bytes, source.readBytes())
    }
    @Test fun nonJpegGalleryCopyUsesFullSourceForConversion() = fixture { archive, source ->
        val converted = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 7)
        val before = source.readBytes()
        val copy = archive.retainPhoto(before) { original ->
            assertArrayEquals(before, original)
            converted
        }
        assertTrue(archive.save(listOf(copy), "Converted") { file, _ ->
            assertArrayEquals(converted, file.readBytes())
        }.isEmpty())
        assertArrayEquals(before, source.readBytes())
    }
    @Test fun safeNamesAndRepeatedNames() {
        assertEquals("Mom's Taco Meat - card 1.jpg", ImportPhotoArchive.photoName("Mom's Taco Meat", 1))
        assertEquals("A_B_C - card 2.jpg", ImportPhotoArchive.photoName("A/B:C", 2))
        assertEquals("Recipe - card 1.jpg", ImportPhotoArchive.photoName("...", 1))
        val used = setOf("Soup - card 1.jpg", "Soup - card 1 (2).jpg")
        assertEquals("Soup - card 1 (3).jpg", ImportPhotoArchive.availableName("Soup - card 1.jpg") { it in used })
    }
}
