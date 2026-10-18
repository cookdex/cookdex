package com.sylph.cookdex

import android.content.Context
import android.os.Build

/** Use the activity's overlaid resources, not a new palette seeded from one tint. */
internal object WallpaperColors {
    fun read(context: Context, dark: Boolean): Map<String, Long>? {
        return read(Build.VERSION.SDK_INT, dark,
            { id -> context.getColor(id).toLong() and 0xffffffffL },
            { name ->
                val id = context.resources.getIdentifier(name, "color", "android")
                context.getColor(id).toLong() and 0xffffffffL
            })
    }

    // Resolver injection keeps the Android-version branches testable on the host.
    internal fun read(api: Int, dark: Boolean, color: (Int) -> Long, legacyColor: (String) -> Long): Map<String, Long>? {
        if (api < 31) return null
        fun role(darkId: Int, lightId: Int) = color(if (dark) darkId else lightId)
        val colors = if (api >= 34) {
            mutableMapOf(
                "primary" to role(android.R.color.system_primary_dark, android.R.color.system_primary_light),
                "onPrimary" to role(android.R.color.system_on_primary_dark, android.R.color.system_on_primary_light),
                "primaryContainer" to role(android.R.color.system_primary_container_dark, android.R.color.system_primary_container_light),
                "onPrimaryContainer" to role(android.R.color.system_on_primary_container_dark, android.R.color.system_on_primary_container_light),
                "primaryFixed" to color(android.R.color.system_primary_fixed),
                "primaryFixedDim" to color(android.R.color.system_primary_fixed_dim),
                "onPrimaryFixed" to color(android.R.color.system_on_primary_fixed),
                "onPrimaryFixedVariant" to color(android.R.color.system_on_primary_fixed_variant),
                "secondary" to role(android.R.color.system_secondary_dark, android.R.color.system_secondary_light),
                "onSecondary" to role(android.R.color.system_on_secondary_dark, android.R.color.system_on_secondary_light),
                "secondaryContainer" to role(android.R.color.system_secondary_container_dark, android.R.color.system_secondary_container_light),
                "onSecondaryContainer" to role(android.R.color.system_on_secondary_container_dark, android.R.color.system_on_secondary_container_light),
                "secondaryFixed" to color(android.R.color.system_secondary_fixed),
                "secondaryFixedDim" to color(android.R.color.system_secondary_fixed_dim),
                "onSecondaryFixed" to color(android.R.color.system_on_secondary_fixed),
                "onSecondaryFixedVariant" to color(android.R.color.system_on_secondary_fixed_variant),
                "tertiary" to role(android.R.color.system_tertiary_dark, android.R.color.system_tertiary_light),
                "onTertiary" to role(android.R.color.system_on_tertiary_dark, android.R.color.system_on_tertiary_light),
                "tertiaryContainer" to role(android.R.color.system_tertiary_container_dark, android.R.color.system_tertiary_container_light),
                "onTertiaryContainer" to role(android.R.color.system_on_tertiary_container_dark, android.R.color.system_on_tertiary_container_light),
                "tertiaryFixed" to color(android.R.color.system_tertiary_fixed),
                "tertiaryFixedDim" to color(android.R.color.system_tertiary_fixed_dim),
                "onTertiaryFixed" to color(android.R.color.system_on_tertiary_fixed),
                "onTertiaryFixedVariant" to color(android.R.color.system_on_tertiary_fixed_variant),
                "error" to role(android.R.color.system_error_dark, android.R.color.system_error_light),
                "onError" to role(android.R.color.system_on_error_dark, android.R.color.system_on_error_light),
                "errorContainer" to role(android.R.color.system_error_container_dark, android.R.color.system_error_container_light),
                "onErrorContainer" to role(android.R.color.system_on_error_container_dark, android.R.color.system_on_error_container_light),
                "surface" to role(android.R.color.system_surface_dark, android.R.color.system_surface_light),
                "onSurface" to role(android.R.color.system_on_surface_dark, android.R.color.system_on_surface_light),
                "surfaceDim" to role(android.R.color.system_surface_dim_dark, android.R.color.system_surface_dim_light),
                "surfaceBright" to role(android.R.color.system_surface_bright_dark, android.R.color.system_surface_bright_light),
                "surfaceContainerLowest" to role(android.R.color.system_surface_container_lowest_dark, android.R.color.system_surface_container_lowest_light),
                "surfaceContainerLow" to role(android.R.color.system_surface_container_low_dark, android.R.color.system_surface_container_low_light),
                "surfaceContainer" to role(android.R.color.system_surface_container_dark, android.R.color.system_surface_container_light),
                "surfaceContainerHigh" to role(android.R.color.system_surface_container_high_dark, android.R.color.system_surface_container_high_light),
                "surfaceContainerHighest" to role(android.R.color.system_surface_container_highest_dark, android.R.color.system_surface_container_highest_light),
                "onSurfaceVariant" to role(android.R.color.system_on_surface_variant_dark, android.R.color.system_on_surface_variant_light),
                "outline" to role(android.R.color.system_outline_dark, android.R.color.system_outline_light),
                "outlineVariant" to role(android.R.color.system_outline_variant_dark, android.R.color.system_outline_variant_light),
                // Inverse roles were not public until API 37. Earlier releases
                // use the standard inverse tones from their system palettes.
                "inverseSurface" to if (api >= 37)
                    role(android.R.color.system_inverse_surface_dark, android.R.color.system_inverse_surface_light)
                    else role(android.R.color.system_neutral1_100, android.R.color.system_neutral1_800),
                "onInverseSurface" to if (api >= 37)
                    role(android.R.color.system_inverse_on_surface_dark, android.R.color.system_inverse_on_surface_light)
                    else role(android.R.color.system_neutral1_800, android.R.color.system_neutral1_50),
                "inversePrimary" to if (api >= 37)
                    role(android.R.color.system_inverse_primary_dark, android.R.color.system_inverse_primary_light)
                    else role(android.R.color.system_accent1_600, android.R.color.system_accent1_200),
            )
        } else {
            // Android 12/13 expose five complete tonal palettes, but no role resources.
            // These are Material 3 tone assignments; preserve each system palette.
            fun tone(palette: String, value: Int): Long {
                val suffix = when (value) { 100 -> 0; 99 -> 10; 95 -> 50; else -> (100 - value) * 10 }
                return legacyColor("system_${palette}_${suffix}")
            }
            fun pair(palette: String, darkTone: Int, lightTone: Int) =
                tone(palette, if (dark) darkTone else lightTone)
            mutableMapOf<String, Long>().apply {
                for ((name, palette) in listOf("primary" to "accent1", "secondary" to "accent2", "tertiary" to "accent3")) {
                    val title = name.replaceFirstChar { it.uppercaseChar() }
                    put(name, pair(palette, 80, 40))
                    put("on$title", pair(palette, 20, 100))
                    put("${name}Container", pair(palette, 30, 90))
                    put("on${title}Container", pair(palette, 90, 10))
                    put("${name}Fixed", tone(palette, 90))
                    put("${name}FixedDim", tone(palette, 80))
                    put("on${title}Fixed", tone(palette, 10))
                    put("on${title}FixedVariant", tone(palette, 30))
                }
                put("surface", pair("neutral1", 10, 99))
                put("onSurface", pair("neutral1", 90, 10))
                put("surfaceDim", pair("neutral1", 10, 90))
                put("surfaceBright", pair("neutral1", 20, 99))
                put("surfaceContainerLowest", pair("neutral1", 0, 100))
                put("surfaceContainerLow", pair("neutral1", 10, 95))
                put("surfaceContainer", pair("neutral1", 10, 95))
                put("surfaceContainerHigh", pair("neutral1", 20, 90))
                put("surfaceContainerHighest", pair("neutral1", 20, 90))
                put("onSurfaceVariant", pair("neutral2", 80, 30))
                put("outline", pair("neutral2", 60, 50))
                put("outlineVariant", pair("neutral2", 30, 80))
                put("inverseSurface", pair("neutral1", 90, 20))
                put("onInverseSurface", pair("neutral1", 20, 95))
                put("inversePrimary", pair("accent1", 40, 80))
                // Android 12/13 do not expose a dynamic error palette.
                put("error", if (dark) 0xffffb4abL else 0xffba1a1aL)
                put("onError", if (dark) 0xff690005L else 0xffffffffL)
                put("errorContainer", if (dark) 0xff93000aL else 0xffffdad6L)
                put("onErrorContainer", if (dark) 0xffffdad6L else 0xff410002L)
            }
        }
        colors["surfaceTint"] = colors.getValue("primary")
        colors["shadow"] = 0xff000000L
        colors["scrim"] = 0xff000000L
        return colors
    }
}
