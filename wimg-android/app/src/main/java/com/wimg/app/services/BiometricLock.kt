package com.wimg.app.services

import android.content.Context
import android.content.SharedPreferences
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Biometric (Fingerprint / Face / device credential) app lock.
 *
 * Mirrors iOS `BiometricLock`: opt-in via Settings, gates the app on cold
 * start and when returning from background. Settings toggle persisted in
 * SharedPreferences under `wimg_lock_enabled`.
 *
 * Combined with `Window.FLAG_SECURE` in MainActivity, the recents thumbnail
 * is blanked while the toggle is on (also prevents screenshots).
 */
object BiometricLock {
    private const val PREFS = "wimg_settings"
    private const val KEY_ENABLED = "wimg_lock_enabled"

    /** True when the gate is up and the main UI should be hidden. */
    var isLocked by mutableStateOf(false)
        private set

    /** Loaded once at process start by [initialize]. */
    var isEnabled by mutableStateOf(false)
        private set

    enum class AvailableMethod { BIOMETRIC_STRONG, BIOMETRIC_WEAK, DEVICE_CREDENTIAL, NONE }

    fun initialize(context: Context) {
        val prefs = prefs(context)
        isEnabled = prefs.getBoolean(KEY_ENABLED, false)
        // Start locked if the user enabled it — first authenticate() unlocks.
        isLocked = isEnabled
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        isEnabled = enabled
        // Engage the lock immediately so the user sees it work right after
        // flipping the toggle — otherwise they'd have to background the app
        // first, which feels broken.
        isLocked = enabled
    }

    fun availableMethod(context: Context): AvailableMethod {
        val mgr = BiometricManager.from(context)
        if (mgr.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            == BiometricManager.BIOMETRIC_SUCCESS) return AvailableMethod.BIOMETRIC_STRONG
        // Most Android emulators (and some real devices) only report class 2
        // fingerprint = BIOMETRIC_WEAK. Without this branch the prompt would
        // ignore the enrolled fingerprint and accept only the device PIN.
        if (mgr.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            == BiometricManager.BIOMETRIC_SUCCESS) return AvailableMethod.BIOMETRIC_WEAK
        if (mgr.canAuthenticate(BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            == BiometricManager.BIOMETRIC_SUCCESS) return AvailableMethod.DEVICE_CREDENTIAL
        return AvailableMethod.NONE
    }

    /** Called when the activity is in foreground — show prompt if locked. */
    fun authenticate(activity: FragmentActivity) {
        if (!isLocked) return
        val method = availableMethod(activity)
        if (method == AvailableMethod.NONE) {
            // Nothing enrolled. Don't auto-unlock — that would silently
            // disable security. Instead leave the LockScreen up so the user
            // sees the "Set up screen lock" message + button.
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                isLocked = false
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                // User cancelled / negative button — leave locked. Lock screen
                // gives them an Entsperren button to retry.
            }
        }

        val prompt = BiometricPrompt(activity, executor, callback)
        // BIOMETRIC_STRONG combines with DEVICE_CREDENTIAL natively.
        // BIOMETRIC_WEAK cannot — pairing them throws IllegalArgumentException.
        // So WEAK runs alone; if the user wants PIN fallback they re-tap.
        val authenticators = when (method) {
            AvailableMethod.BIOMETRIC_STRONG -> BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
            AvailableMethod.BIOMETRIC_WEAK -> BiometricManager.Authenticators.BIOMETRIC_WEAK
            AvailableMethod.DEVICE_CREDENTIAL -> BiometricManager.Authenticators.DEVICE_CREDENTIAL
            AvailableMethod.NONE -> return
        }

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("wimg")
            .setSubtitle("App entsperren")
            .apply {
                // BIOMETRIC_WEAK alone can't use setAllowedAuthenticators with
                // DEVICE_CREDENTIAL → need a negative button instead.
                if (method == AvailableMethod.BIOMETRIC_WEAK) {
                    setNegativeButtonText("Abbrechen")
                }
            }
            .setAllowedAuthenticators(authenticators)
            .build()

        prompt.authenticate(info)
    }

    /** Called from Activity lifecycle — re-lock when returning from background. */
    fun onResume() {
        if (isEnabled) isLocked = true
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
