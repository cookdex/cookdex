package com.sylph.cookdex

import android.app.Activity
import android.os.Build
import android.os.PerformanceHintManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Optional API31+ feedback, serialized on the platform thread. */
class FramePerformanceHints(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.sylph.cookdex.dev/frame-hints")
    private var backend: Api31? = null
    private var token = 0L
    private var paused = false

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "open" -> {
                        closeSession()
                        val ui = call.argument<Number>("uiTid")?.toInt() ?: 0
                        val target = call.argument<Number>("targetNanos")?.toLong() ?: 0
                        if (Build.VERSION.SDK_INT < 31 || paused || ui <= 0 || target <= 0) {
                            result.success(null)
                        } else {
                            backend = Api31.open(activity, ui, target)
                            result.success(if (backend != null) ++token else null)
                        }
                    }
                    "report" -> {
                        val id = call.argument<Number>("session")?.toLong()
                        val target = call.argument<Number>("targetNanos")?.toLong() ?: 0
                        val work = call.argument<LongArray>("workNanos")
                        val current = backend
                        if (id != token || current == null || paused || target <= 0 || work == null || work.size > 200) {
                            result.success(false)
                        } else {
                            current.report(target, work)
                            result.success(true)
                        }
                    }
                    "close" -> {
                        if ((call.arguments as? Number)?.toLong() == token) closeSession()
                        result.success(null)
                    }
                    "workload" -> {
                        val current = backend
                        if (call.argument<Number>("session")?.toLong() != token || current == null || paused) {
                            result.success(38) // No live session; ordinary hints are unaffected.
                        } else {
                            result.success(current.workload(call.argument<Boolean>("increased") == true))
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                if (call.method == "workload") {
                    // Workload hints are optional; their failure must neither
                    // close ordinary frame reporting nor change reply type.
                    result.success(38)
                } else {
                    closeSession()
                    if (call.method == "open") result.success(null) else result.success(false)
                }
            }
        }
    }

    fun setResumed(resumed: Boolean) {
        paused = !resumed
        setImmediateResumed(resumed)
        if (paused) {
            closeSession()
        }
    }

    private fun closeSession() {
        val old = backend
        backend = null
        try { old?.close() } catch (_: Exception) { }
    }

    private fun setImmediateResumed(resumed: Boolean) {
        if (workloadLibraryLoaded) {
            try { setUiResumedNative(resumed) } catch (_: LinkageError) { }
        }
    }

    fun close() {
        setImmediateResumed(false)
        closeSession()
        channel.setMethodCallHandler(null)
    }

    companion object {
        private external fun setUiResumedNative(resumed: Boolean)
        private external fun notifyWorkloadNative(session: PerformanceHintManager.Session, increased: Boolean): Int
        private val workloadLibraryLoaded by lazy {
            try { System.loadLibrary("cookdex_bridge"); true } catch (_: LinkageError) { false }
        }
    }

    @android.annotation.SuppressLint("NewApi")
    private class Api31(private val session: PerformanceHintManager.Session, private var target: Long) {
        fun workload(increased: Boolean): Int {
            // Java sendHint is a hidden TestApi, including on API34/35. The
            // supported public native equivalent and Java-session borrowing
            // both begin at API36. Never reflect into hidden Android APIs.
            if (Build.VERSION.SDK_INT < 36 || !workloadLibraryLoaded) return 38
            return try { notifyWorkloadNative(session, increased) } catch (_: LinkageError) { 38 }
        }
        fun report(newTarget: Long, work: LongArray) {
            if (newTarget != target) {
                session.updateTargetWorkDuration(newTarget)
                target = newTarget
            }
            for (duration in work) if (duration > 0) session.reportActualWorkDuration(duration)
        }
        fun close() = session.close()

        companion object {
            fun open(activity: Activity, ui: Int, target: Long): Api31? {
                val tasks = File("/proc/self/task")
                if (!File(tasks, "$ui/comm").isFile) return null
                // Pinned Flutter names its raster thread <engine-counter>.raster.
                // Refuse ambiguity rather than hinting unrelated worker threads.
                val raster = tasks.listFiles()?.mapNotNull { task ->
                    try {
                        if (Regex("[0-9]+\\.raster").matches(File(task, "comm").readText().trim())) task.name.toIntOrNull() else null
                    } catch (_: Exception) { null }
                } ?: return null
                if (raster.size != 1 || raster.single() == ui) return null
                val manager = activity.getSystemService(PerformanceHintManager::class.java) ?: return null
                val session = manager.createHintSession(intArrayOf(ui, raster.single()), target) ?: return null
                return Api31(session, target)
            }
        }
    }
}
