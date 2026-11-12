package com.sylph.cookdex

import android.content.pm.PackageManager
import org.junit.Assert.assertEquals
import org.junit.Test

class CameraPermissionTest {
    @Test fun classifiesGrantDenialsAndInterruptedPrompt() {
        assertEquals("granted", cameraPermissionAnswer(PackageManager.PERMISSION_GRANTED, false))
        assertEquals("denied", cameraPermissionAnswer(PackageManager.PERMISSION_DENIED, true))
        assertEquals("blocked", cameraPermissionAnswer(PackageManager.PERMISSION_DENIED, false))
        assertEquals("cancelled", cameraPermissionAnswer(null, false))
    }
}
