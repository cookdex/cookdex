package com.sylph.cookdex

/** Activity-local, one-shot startup cover. No engine or import queue ownership. */
internal class StartupSplashState(
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val dismiss: (Long) -> Unit,
) {
    companion object {
        const val TIMEOUT_MS = 3000L
        const val FADE_MS = 200L
    }

    var finished = false
        private set
    var exitDuration = 0L
        private set
    var timedOut = false
        private set
    private var cancelTimeout: (() -> Unit)? = null

    fun start() {
        if (!finished && cancelTimeout == null) {
            cancelTimeout = schedule(TIMEOUT_MS) { timeout() }
        }
    }

    fun ready(immediate: Boolean) {
        if (finished) return
        finished = true
        exitDuration = if (immediate) 0L else FADE_MS
        cancelTimeout?.invoke()
        cancelTimeout = null
        dismiss(exitDuration)
    }

    fun timeout() {
        if (finished) return
        timedOut = true
        ready(true)
    }

    /** Replay a readiness/timeout signal that arrived before the cover view. */
    fun attached() {
        if (finished) dismiss(exitDuration)
    }

    fun close() {
        cancelTimeout?.invoke()
        cancelTimeout = null
        finished = true
    }
}
