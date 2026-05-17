package com.wimg.app

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import com.wimg.app.services.BiometricLock
import com.wimg.app.ui.LockScreen
import com.wimg.app.ui.navigation.WimgNavigation
import com.wimg.app.ui.theme.WimgTheme

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        BiometricLock.initialize(this)
        applySecureFlag()
        setContent {
            WimgTheme {
                Box(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                    WimgNavigation()
                    if (BiometricLock.isLocked) {
                        LockScreen(activity = this@MainActivity)
                    }
                }
                // Auto-prompt on cold start when locked.
                LaunchedEffect(BiometricLock.isLocked) {
                    if (BiometricLock.isLocked) {
                        BiometricLock.authenticate(this@MainActivity)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        applySecureFlag()
        BiometricLock.onResume()
        if (BiometricLock.isLocked) {
            BiometricLock.authenticate(this)
        }
    }

    /**
     * FLAG_SECURE: blanks the recents thumbnail (system shows a black panel
     * instead of the live UI) and prevents screenshots / screen recording.
     * Applied only when the user has opted into the app lock.
     */
    private fun applySecureFlag() {
        if (BiometricLock.isEnabled) {
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
