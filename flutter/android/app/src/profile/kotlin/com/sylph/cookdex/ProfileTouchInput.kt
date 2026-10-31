package com.sylph.cookdex

import android.app.Activity
import android.app.Instrumentation
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Android input-dispatcher gestures, only inside the isolated profiling APK. */
object ProfileTouchInput {
    @JvmStatic
    fun install(activity: Activity, engine: FlutterEngine) {
        check(activity.packageName == "com.sylph.cookdex.dev.profile")
        val worker = Executors.newSingleThreadExecutor()
        MethodChannel(engine.dartExecutor.binaryMessenger, "cookdex/profile-touch")
            .setMethodCallHandler { call, result ->
                if (call.method != "gesture") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                @Suppress("UNCHECKED_CAST")
                val path = (call.arguments as? List<List<Number>>)?.map {
                    require(it.size == 3)
                    Triple(it[0].toLong(), it[1].toFloat(), it[2].toFloat())
                } ?: error("Expected timed touch coordinates")
                require(path.size in 2..2400 && path.first().first == 0L)
                require(path.last().first in 1..15000)
                require(path.zipWithNext().all { (a, b) -> b.first > a.first })
                worker.execute {
                    val injector = Instrumentation()
                    val down = SystemClock.uptimeMillis()
                    var sent = 0
                    try {
                        for ((index, point) in path.withIndex()) {
                            val remaining = down + point.first - SystemClock.uptimeMillis()
                            if (remaining > 0) SystemClock.sleep(remaining)
                            val action = when (index) {
                                0 -> MotionEvent.ACTION_DOWN
                                path.lastIndex -> MotionEvent.ACTION_UP
                                else -> MotionEvent.ACTION_MOVE
                            }
                            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(),
                                action, point.second, point.third, 0)
                            event.source = InputDevice.SOURCE_TOUCHSCREEN
                            try { injector.sendPointerSync(event) } finally { event.recycle() }
                            sent++
                        }
                        val elapsed = SystemClock.uptimeMillis() - down
                        activity.runOnUiThread { result.success(mapOf("events" to sent, "elapsedMs" to elapsed)) }
                    } catch (failure: Exception) {
                        activity.runOnUiThread { result.error("touch", failure.toString(), null) }
                    }
                }
            }
    }
}
