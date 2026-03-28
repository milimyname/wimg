package com.wimg.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.wimg.app.ui.navigation.WimgNavigation
import com.wimg.app.ui.theme.WimgTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WimgTheme {
                WimgNavigation()
            }
        }
    }
}
