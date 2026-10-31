package com.sylph.cookdex

import org.junit.Assert.*
import org.junit.Test

class StartupSplashStateTest {
    private class Clock {
        var now = 0L
        var deadline = 0L
        var callback: (() -> Unit)? = null
        fun schedule(delay: Long, action: () -> Unit): () -> Unit {
            deadline = now + delay
            callback = action
            return { callback = null }
        }
        fun advance(ms: Long) {
            now += ms
            if (now >= deadline) callback?.invoke()
        }
    }

    @Test fun readyFadesOnceAndCancelsTimeout() {
        val clock = Clock()
        val durations = mutableListOf<Long>()
        val state = StartupSplashState(clock::schedule) { durations.add(it) }
        state.start()
        state.ready(false)
        state.ready(false)
        clock.advance(3000)
        assertEquals(listOf(200L), durations)
        assertNull(clock.callback)
        assertTrue(state.finished)
    }

    @Test fun stalledStartupDismissesAtThreeSecondsWithoutFade() {
        val clock = Clock()
        val durations = mutableListOf<Long>()
        val state = StartupSplashState(clock::schedule) { durations.add(it) }
        state.start()
        clock.advance(2999)
        assertFalse(state.finished)
        assertTrue(durations.isEmpty())
        state.start()
        clock.advance(1)
        assertTrue(state.finished)
        state.ready(false)
        assertEquals(listOf(0L), durations)
    }

    @Test fun errorRecoveryAndEmptyBypassFade() {
        val clock = Clock()
        val durations = mutableListOf<Long>()
        val state = StartupSplashState(clock::schedule) { durations.add(it) }
        state.start()
        state.ready(true)
        clock.advance(3000)
        assertEquals(listOf(0L), durations)
    }

    @Test fun destroyedActivityCancelsDeadlineAndIgnoresLateReady() {
        val clock = Clock()
        val durations = mutableListOf<Long>()
        val state = StartupSplashState(clock::schedule) { durations.add(it) }
        state.start()
        state.close()
        clock.advance(3000)
        state.ready(false)
        assertNull(clock.callback)
        assertTrue(durations.isEmpty())
    }

    @Test fun readyBeforeListenerAttachmentIsReplayedWithoutStartingAnotherTimer() {
        val clock = Clock()
        var attached = false
        val durations = mutableListOf<Long>()
        val state = StartupSplashState(clock::schedule) { if (attached) durations.add(it) }
        state.ready(false)
        state.start()
        assertNull(clock.callback)
        attached = true
        state.attached()
        assertEquals(listOf(200L), durations)
    }

    @Test fun nativeDeadlineNeedsNeitherDartNorAnAttachedCover() {
        val clock = Clock()
        var attached = false
        val durations = mutableListOf<Long>()
        val state = StartupSplashState(clock::schedule) { if (attached) durations.add(it) }
        state.start()
        clock.advance(3000)
        assertTrue(state.timedOut)
        assertTrue(state.finished)
        attached = true
        state.attached()
        assertEquals(listOf(0L), durations)
        state.ready(false)
        assertEquals(listOf(0L), durations)
    }
}
