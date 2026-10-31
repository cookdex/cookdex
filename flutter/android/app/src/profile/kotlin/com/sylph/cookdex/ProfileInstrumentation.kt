package com.sylph.cookdex

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle

/** Started explicitly by guarded adb; gives Android test input its normal owner. */
class ProfileInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        check(targetContext.packageName == "com.sylph.cookdex.dev.profile")
        start()
    }

    override fun onStart() {
        startActivitySync(Intent(targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("enable-dart-profiling", true)
            .putExtra("endless-trace-buffer", true))
    }
}
