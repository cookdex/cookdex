package com.sylph.cookdex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingShareTypesTest {
    @Test fun aBrowserPageAddressIsDistinctFromAnAttachmentOrCaption() {
        assertTrue(IncomingShareTypes.isWebLink("https://recipes.example.test/dinner?serves=4"))
        assertFalse(IncomingShareTypes.isWebLink("content://fixture/recipe.txt"))
        assertFalse(IncomingShareTypes.isWebLink("A recipe and a link https://recipes.example.test/dinner"))
    }

    @Test fun explicitRecipeTextWinsOverClipWebUrl() {
        val recipe = "  Lemon rice\n1 cup rice\nStir until warm.  "
        val url = "https://recipes.example.test/lemon"
        assertEquals(recipe, IncomingShareTypes.sharedMessage(recipe, "link preview", url))
        assertEquals(recipe, IncomingShareTypes.sharedMessage("  ", recipe, url))
        assertEquals(url, IncomingShareTypes.sharedMessage(null, "  ", url))
    }

    @Test fun attachmentTypeAndNameMustAgree() {
        val types = IncomingShareTypes
        assertEquals("text/plain", types.normalize(" Text/Plain; charset=UTF-8 "))
        assertTrue(types.isTextFile("application/octet-stream", "", "Fictional soup.TXT"))
        assertTrue(types.isTextFile("*/*", "text/plain", null))
        assertTrue(types.isTextFile("text/plain", "application/octet-stream", null))
        assertTrue(types.isTextFile("application/txt", "", "Fictional soup.txt"))
        assertTrue(types.isTextFile("", "", "Fictional soup.txt"))
        assertFalse(types.isTextFile("application/octet-stream", "", null))
        assertFalse(types.isTextFile("text/plain", "text/plain", "Fictional soup.txt.zip"))
        assertFalse(types.isTextFile("*/*", "application/pdf", "Fictional soup.txt"))
        assertFalse(types.isTextFile("text/html", "", "Fictional soup.txt"))
        assertFalse(types.isTextFile("image/png", "", "Fictional soup.txt"))
    }

    @Test fun imageStreamsAndTextMessagesAreDistinct() {
        val types = IncomingShareTypes
        assertTrue(types.isPhoto("image/*", "application/octet-stream"))
        assertTrue(types.isPhoto("*/*", "image/jpeg"))
        assertFalse(types.isPhoto("text/plain", "image/jpeg"))
        assertFalse(types.isPhoto("image/png", "text/plain"))
        assertTrue(types.allowsMessage("text/uri-list"))
        assertTrue(types.allowsMessage("text/plain"))
        assertFalse(types.allowsMessage("application/octet-stream"))
    }
}
