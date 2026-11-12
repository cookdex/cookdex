package com.sylph.cookdex

import java.util.Locale

internal object IncomingShareTypes {
    const val MAX_TEXT = 5 * 1024 * 1024

    private val plain = setOf(
        "text/plain", "text/txt", "text/x-plain", "application/text", "application/txt",
        "application/x-txt",
    )
    private val generic = setOf(
        "", "*/*", "text/*", "application/*", "application/octet-stream",
        "binary/octet-stream", "application/unknown", "application/x-unknown-content-type",
    )

    fun normalize(value: String?) =
        value.orEmpty().substringBefore(';').trim().lowercase(Locale.ROOT)

    fun allowsMessage(type: String) =
        type in plain || type in setOf("", "*/*", "text/*", "text/uri-list")

    fun isWebLink(text: CharSequence): Boolean {
        if (text.length > 8192) return false
        val uri = try { java.net.URI(text.toString().trim()) } catch (_: java.net.URISyntaxException) { return false }
        return uri.scheme in setOf("https", "http") && !uri.host.isNullOrEmpty()
    }

    /** A shared recipe can carry a web URL as metadata. Keep the sender's text verbatim. */
    fun sharedMessage(extra: CharSequence?, clip: CharSequence?, webUrl: String?): String {
        val text = sequenceOf(extra, clip, webUrl).filterNotNull().firstOrNull {
            require(it.length <= MAX_TEXT)
            it.isNotBlank()
        }?.toString() ?: throw IllegalArgumentException()
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_TEXT)
        return text
    }

    /** Opaque attachment IDs have no useful suffix. Use the display name from
     * the provider when available. Generic MIME alone cannot identify text. */
    fun isTextFile(declared: String, resolved: String, name: String?): Boolean {
        if ((declared !in plain && declared !in generic) ||
            (resolved !in plain && resolved !in generic)) return false
        val suppliedName = name.orEmpty()
        if (suppliedName.endsWith(".txt", ignoreCase = true)) return true
        if ('.' in suppliedName) return false
        return declared in plain || resolved in plain
    }

    fun isPhoto(declared: String, resolved: String) =
        (declared.startsWith("image/") && (resolved.startsWith("image/") || resolved in generic)) ||
            (resolved.startsWith("image/") && declared in generic)
}
