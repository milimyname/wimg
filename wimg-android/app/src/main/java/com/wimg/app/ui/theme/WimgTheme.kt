package com.wimg.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

/**
 * Card style modifier matching iOS .wimgCard():
 * cardBg background + rounded corners + subtle shadow.
 */
@Composable
fun Modifier.wimgCard(radius: RoundedCornerShape = WimgShapes.medium): Modifier {
    return this
        .shadow(elevation = 0.5.dp, shape = radius, ambientColor = Color.Black.copy(alpha = 0.03f))
        .clip(radius)
        .background(MaterialTheme.colorScheme.surface)
}

/**
 * Hero card style matching iOS .wimgHero():
 * accent background + subtle shadow + XL radius.
 */
@Composable
fun Modifier.wimgHero(): Modifier {
    return this
        .shadow(elevation = 2.dp, shape = WimgShapes.xl, ambientColor = Color.Black.copy(alpha = 0.06f))
        .clip(WimgShapes.xl)
        .background(WimgColors.accent)
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

// Typography matching iOS .rounded design
private val WimgTypography = Typography(
    headlineLarge = TextStyle(fontWeight = FontWeight.Black, fontSize = 32.sp, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontWeight = FontWeight.Black, fontSize = 28.sp, letterSpacing = (-0.5).sp),
    headlineSmall = TextStyle(fontWeight = FontWeight.Bold, fontSize = 24.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 22.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.Bold, fontSize = 17.sp),
    titleSmall = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp),
    bodyLarge = TextStyle(fontWeight = FontWeight.Normal, fontSize = 17.sp),
    bodyMedium = TextStyle(fontWeight = FontWeight.Normal, fontSize = 15.sp),
    bodySmall = TextStyle(fontWeight = FontWeight.Normal, fontSize = 13.sp),
    labelLarge = TextStyle(fontWeight = FontWeight.Bold, fontSize = 15.sp, letterSpacing = 0.5.sp),
    labelMedium = TextStyle(fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 0.8.sp),
    labelSmall = TextStyle(fontWeight = FontWeight.Bold, fontSize = 11.sp, letterSpacing = 0.5.sp),
)

/** Global app state — mutate from Settings to trigger recomposition */
object ThemeState {
    var mode by mutableIntStateOf(-1) // -1=system, 1=light, 2=dark
}

object LocaleState {
    var locale by mutableStateOf("de") // "de" or "en"
}

@Composable
fun WimgTheme(
    content: @Composable () -> Unit,
) {
    // Read stored theme + locale on first composition
    val context = LocalView.current.context
    LaunchedEffect(Unit) {
        val prefs = context.getSharedPreferences("wimg", 0)
        val storedTheme = prefs.getInt("wimg_theme", -1)
        if (ThemeState.mode != storedTheme) ThemeState.mode = storedTheme
        val storedLocale = prefs.getString("wimg_locale", "de") ?: "de"
        if (LocaleState.locale != storedLocale) LocaleState.locale = storedLocale
    }

    val darkTheme = when (ThemeState.mode) {
        1 -> false  // Hell
        2 -> true   // Dunkel
        else -> isSystemInDarkTheme() // System
    }
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
        typography = WimgTypography,
        content = content,
    )
}
