package com.wimg.app

import android.app.Application
import com.wimg.app.bridge.LibWimg

class WimgApp : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            LibWimg.initialize(this)
        } catch (e: Exception) {
            // Store error for display in MainActivity
            initError = e.message
        }
    }

    companion object {
        var initError: String? = null
    }
}
