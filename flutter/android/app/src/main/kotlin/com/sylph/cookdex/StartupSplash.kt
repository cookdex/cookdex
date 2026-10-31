package com.sylph.cookdex

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.window.SplashScreenView

/** Keep Android's launch artwork while Flutter lays out and rasters the library. */
internal class StartupSplash(
    private val activity: Activity,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var legacy: View? = null
    private var system: SplashScreenView? = null
    private var loading: View? = null
    private var hasFrame = false
    private var attached = false
    private var hiddenAt: Long? = null
    private var hiddenListener: ((Long) -> Unit)? = null

    // Read-only timing hook used by the permanent isolated profile build.
    fun whenHidden(listener: (Long) -> Unit) {
        hiddenAt?.let { listener(it); return }
        hiddenListener = listener
    }

    private fun hidden() {
        if (hiddenAt != null) return
        val time = System.currentTimeMillis()
        hiddenAt = time
        hiddenListener?.invoke(time)
        hiddenListener = null
    }
    private val state = StartupSplashState(
        schedule = { delay, action ->
            val callback = Runnable { action(); showLoadingIfNeeded() }
            handler.postDelayed(callback, delay)
            val cancel: () -> Unit = { handler.removeCallbacks(callback) }
            cancel
        },
        dismiss = ::dismiss,
    )

    fun start() {
        state.start()
        if (Build.VERSION.SDK_INT >= 31) {
            activity.splashScreen.setOnExitAnimationListener { view ->
                system = view
                state.attached()
            }
        }
    }

    fun attach() {
        attached = true
        showLoadingIfNeeded()
        if (Build.VERSION.SDK_INT >= 31 || state.finished) return
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        legacy = View(activity).apply {
            setBackgroundResource(com.sylph.cookdex.R.drawable.launch_background)
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            content.addView(this, ViewGroup.LayoutParams(-1, -1))
        }
        state.attached()
    }

    fun ready(immediate: Boolean) {
        firstFrame()
        state.ready(immediate)
    }

    fun firstFrame() {
        hasFrame = true
        loading?.let { (it.parent as? ViewGroup)?.removeView(it) }
        loading = null
    }

    private fun showLoadingIfNeeded() {
        if (!attached || !state.timedOut || hasFrame || loading != null) return
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        loading = FrameLayout(activity).apply {
            setBackgroundColor(activity.getColor(com.sylph.cookdex.R.color.cookdex_launch_background))
            isClickable = true
            contentDescription = "Loading cookdex"
            addView(ProgressBar(activity), FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
            content.addView(this, ViewGroup.LayoutParams(-1, -1))
        }
    }

    private fun dismiss(duration: Long) {
        legacy?.let { view ->
            if (duration == 0L) { (view.parent as? ViewGroup)?.removeView(view); hidden() }
            else view.animate().alpha(0f).setDuration(duration).withEndAction {
                (view.parent as? ViewGroup)?.removeView(view)
                hidden()
            }.start()
        }
        if (Build.VERSION.SDK_INT >= 31) system?.let { view ->
            if (duration == 0L) { view.remove(); hidden() }
            else view.animate().alpha(0f).setDuration(duration).withEndAction {
                view.remove()
                hidden()
            }.start()
        }
    }

    fun close() {
        hiddenListener = null
        state.close()
        firstFrame()
        legacy?.animate()?.cancel()
        legacy?.let { (it.parent as? ViewGroup)?.removeView(it) }
        legacy = null
        if (Build.VERSION.SDK_INT >= 31) {
            activity.splashScreen.clearOnExitAnimationListener()
            system?.animate()?.cancel()
            system?.remove()
        }
        system = null
    }
}
