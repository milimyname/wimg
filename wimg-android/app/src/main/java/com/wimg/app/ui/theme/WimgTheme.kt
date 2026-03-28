package com.wimg.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat

// wimg design tokens — matching iOS WimgTheme exactly
object WimgColors {
    val accent = Color(0xFFFFE97D)
    val accentHover = Color(0xFFFFE052)
    val heroText = Color(0xFF1A1A1A)

    // Light
    val bgLight = Color(0xFFFAF9F6)
    val cardBgLight = Color.White
    val textLight = Color(0xFF1A1A1A)
    val textSecondaryLight = Color(0xFF8E8E93)
    val borderLight = Color(0xFFF0ECE6)

    // Dark
    val bgDark = Color(0xFF111114)
    val cardBgDark = Color(0xFF1C1C1E)
    val textDark = Color.White
    val textSecondaryDark = Color(0xFF999A9E)
    val borderDark = Color(0x0DFFFFFF) // white 5%
}

object WimgShapes {
    val small = RoundedCornerShape(20.dp)
    val medium = RoundedCornerShape(24.dp)
    val large = RoundedCornerShape(28.dp)
    val xl = RoundedCornerShape(32.dp)
}

private val LightColorScheme = lightColorScheme(
    primary = WimgColors.accent,
    onPrimary = WimgColors.heroText,
    background = WimgColors.bgLight,
    surface = WimgColors.cardBgLight,
    onBackground = WimgColors.textLight,
    onSurface = WimgColors.textLight,
    outline = WimgColors.borderLight,
    surfaceVariant = WimgColors.bgLight,
    onSurfaceVariant = WimgColors.textSecondaryLight,
)

private val DarkColorScheme = darkColorScheme(
    primary = WimgColors.accent,
    onPrimary = WimgColors.heroText,
    background = WimgColors.bgDark,
    surface = WimgColors.cardBgDark,
    onBackground = WimgColors.textDark,
    onSurface = WimgColors.textDark,
    outline = WimgColors.borderDark,
    surfaceVariant = WimgColors.bgDark,
    onSurfaceVariant = WimgColors.textSecondaryDark,
)

@Composable
fun WimgTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            val insetsController = WindowCompat.getInsetsController(window, view)
            insetsController.isAppearanceLightStatusBars = !darkTheme
            insetsController.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content,
    )
}
