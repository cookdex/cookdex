package com.sylph.cookdex

/** Paths for values the cook explicitly selects. New settings stay private by default. */
internal object PhoneSettings {
    enum class Kind { OBJECT, TEXT, BOOLEAN, NUMBER, NAMES, NAME_GROUPS }

    private val ui = mapOf(
        "themeMode" to Kind.TEXT, "wallpaperColors" to Kind.BOOLEAN,
        "fields" to Kind.NAMES, "sort" to Kind.TEXT, "view" to Kind.TEXT,
        "favoritesOnly" to Kind.BOOLEAN, "recipeTextSize" to Kind.TEXT,
        "shoppingKeepAwake" to Kind.BOOLEAN, "useAiForLink" to Kind.BOOLEAN,
        "youtubeWatchModel" to Kind.TEXT, "saveImportPhotos" to Kind.BOOLEAN,
        "checkUpdatesAutomatically" to Kind.BOOLEAN, "smartCreate" to Kind.OBJECT,
        "keptSeparate" to Kind.OBJECT,
    )
    private val create = mapOf(
        "staples" to Kind.NAMES, "avoid" to Kind.NAMES, "otherPreferences" to Kind.TEXT,
        "servings" to Kind.NUMBER, "extraIngredients" to Kind.NUMBER,
        "photoModel" to Kind.TEXT, "ideaModel" to Kind.TEXT, "recipeModel" to Kind.TEXT,
        "photoThinking" to Kind.TEXT, "ideaThinking" to Kind.TEXT, "recipeThinking" to Kind.TEXT,
        "retiredModels" to Kind.OBJECT,
    )

    fun kind(parent: String, field: String): Kind? = when (parent) {
        "ui" -> ui[field]
        "smartCreate" -> create[field]
        "keptSeparate" -> if (field == "ingredients" || field == "tags") Kind.NAME_GROUPS else null
        "retiredModels" -> if (field in setOf("photo", "ideas", "recipe")) Kind.TEXT else null
        "smart" -> if (field == "model" || field == "effort") Kind.TEXT else null
        "settings" -> if (field == "ui" || field == "smart") Kind.OBJECT else null
        else -> null
    }
}
