package com.sylph.cookdex

import org.junit.Assert.*
import org.junit.Test

class WallpaperColorsTest {
    @Test fun unsupportedAndroidDoesNotReadResources() {
        assertNull(WallpaperColors.read(30, false,
            { error("Unexpected resource read") }, { error("Unexpected legacy read") }))
    }

    @Test fun android14UsesTheSelectedRolesInsteadOfReseedingAnAccent() {
        for (dark in listOf(false, true)) {
            val result = WallpaperColors.read(34, dark, { it.toLong() },
                { error("Modern Android must use its role resources") })!!
            assertEquals(46, result.size)
            assertEquals((if (dark) android.R.color.system_primary_dark else android.R.color.system_primary_light).toLong(), result["primary"])
            assertEquals((if (dark) android.R.color.system_secondary_dark else android.R.color.system_secondary_light).toLong(), result["secondary"])
            assertEquals((if (dark) android.R.color.system_surface_container_high_dark else android.R.color.system_surface_container_high_light).toLong(), result["surfaceContainerHigh"])
            assertEquals((if (dark) android.R.color.system_error_dark else android.R.color.system_error_light).toLong(), result["error"])
            assertEquals(android.R.color.system_primary_fixed.toLong(), result["primaryFixed"])
            assertEquals(result["primary"], result["surfaceTint"])
        }
    }

    @Test fun android12And13KeepAllFiveSystemPalettes() {
        for (api in listOf(31, 32, 33)) {
            for (dark in listOf(false, true)) {
                val names = mutableListOf<String>()
                val result = WallpaperColors.read(api, dark,
                    { error("Legacy Android must use tonal resources") },
                    { name ->
                        names.add(name)
                        // Resolve every requested public name; catches bad tone suffixes.
                        android.R.color::class.java.getField(name).getInt(null).toLong()
                    })!!
                assertEquals(46, result.size)
                val tone = if (dark) 200 else 600
                assertEquals(android.R.color::class.java.getField("system_accent1_$tone").getInt(null).toLong(), result["primary"])
                assertEquals(android.R.color::class.java.getField("system_accent2_$tone").getInt(null).toLong(), result["secondary"])
                for (palette in listOf("accent1", "accent2", "accent3", "neutral1", "neutral2")) {
                    assertTrue("Missing $palette", names.any { it.startsWith("system_${palette}_") })
                }
            }
        }
    }

    @Test fun inverseRolesRespectTheirApi37Introduction() {
        val newerIds = setOf(
            android.R.color.system_inverse_surface_dark, android.R.color.system_inverse_surface_light,
            android.R.color.system_inverse_on_surface_dark, android.R.color.system_inverse_on_surface_light,
            android.R.color.system_inverse_primary_dark, android.R.color.system_inverse_primary_light,
        )
        for (api in 34..37) {
            for (dark in listOf(false, true)) {
                val result = WallpaperColors.read(api, dark, { id ->
                    check(api >= 37 || id !in newerIds) { "Resource $id unavailable on API $api" }
                    id.toLong()
                }, { error("Unexpected legacy lookup") })!!
                val expectedSurface = if (api >= 37) {
                    if (dark) android.R.color.system_inverse_surface_dark else android.R.color.system_inverse_surface_light
                } else {
                    if (dark) android.R.color.system_neutral1_100 else android.R.color.system_neutral1_800
                }
                val expectedOnSurface = if (api >= 37) {
                    if (dark) android.R.color.system_inverse_on_surface_dark else android.R.color.system_inverse_on_surface_light
                } else {
                    if (dark) android.R.color.system_neutral1_800 else android.R.color.system_neutral1_50
                }
                val expectedPrimary = if (api >= 37) {
                    if (dark) android.R.color.system_inverse_primary_dark else android.R.color.system_inverse_primary_light
                } else {
                    if (dark) android.R.color.system_accent1_600 else android.R.color.system_accent1_200
                }
                assertEquals(expectedSurface.toLong(), result["inverseSurface"])
                assertEquals(expectedOnSurface.toLong(), result["onInverseSurface"])
                assertEquals(expectedPrimary.toLong(), result["inversePrimary"])
            }
        }
    }
}
