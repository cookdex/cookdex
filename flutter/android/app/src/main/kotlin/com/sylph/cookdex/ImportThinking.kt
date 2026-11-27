package com.sylph.cookdex

import java.io.IOException

/** Keep the legacy backup field readable by older installations. */
internal object ImportThinking {
    private val legacy = setOf("standard", "thorough")
    private val levels = setOf("default", "minimal", "low", "medium", "high")

    fun backup(value: String?): Pair<String?, String?> {
        if (value == null || value in legacy) return value to null
        if (value !in levels) throw IOException("Invalid import thinking.")
        return (if (value == "high") "thorough" else "standard") to value
    }

    fun restore(effort: String?, thinking: String?): String? {
        if (effort != null && effort !in legacy) throw IOException("Invalid import effort.")
        if (thinking != null && thinking !in levels) throw IOException("Invalid import thinking.")
        return thinking ?: effort
    }
}
