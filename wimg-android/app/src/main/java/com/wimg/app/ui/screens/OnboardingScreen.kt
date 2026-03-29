package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wimg.app.ui.theme.WimgColors
import com.wimg.app.ui.theme.WimgShapes
import kotlinx.coroutines.launch

private data class OnboardingCard(
    val title: String,
    val subtitle: String,
    val emoji: String,
    val color: Color,
)

private val cards = listOf(
    OnboardingCard(
        "Deine Finanzen, auf deinem Gerät",
        "Keine Cloud, kein Konto. Deine Daten bleiben auf deinem Gerät — lokal, privat, offline.",
        "🔒",
        Color(0xFF34C759),
    ),
    OnboardingCard(
        "Importiere deine Bankdaten",
        "Lade eine CSV-Datei von Comdirect, Trade Republic oder Scalable Capital hoch.",
        "📥",
        Color(0xFF007AFF),
    ),
    OnboardingCard(
        "Sparziele & Vermögen",
        "Setze Sparziele, verfolge deinen Fortschritt und sieh dein Nettovermögen über die Zeit.",
        "⭐",
        Color(0xFF5AC8FA),
    ),
    OnboardingCard(
        "Steuern & Sync",
        "Finde absetzbare Ausgaben für deine Steuererklärung. Synchronisiere optional zwischen Geräten.",
        "📊",
        Color(0xFFFF9500),
    ),
)

@Composable
fun OnboardingScreen(onComplete: () -> Unit) {
    val pagerState = rememberPagerState(pageCount = { cards.size })
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))

        HorizontalPager(
            state = pagerState,
            modifier = Modifier.weight(1f),
        ) { page ->
            val card = cards[page]
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Box(
                    modifier = Modifier
                        .size(100.dp)
                        .clip(CircleShape)
                        .background(card.color.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(card.emoji, fontSize = 40.sp)
                }
                Spacer(Modifier.height(32.dp))
                Text(
                    card.title,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    card.subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 24.dp),
                )
            }
        }

        // Page indicators
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(vertical = 24.dp),
        ) {
            repeat(cards.size) { i ->
                Box(
                    modifier = Modifier
                        .size(if (i == pagerState.currentPage) 10.dp else 8.dp)
                        .clip(CircleShape)
                        .background(
                            if (i == pagerState.currentPage) WimgColors.accent
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                        ),
                )
            }
        }

        // Button
        Button(
            onClick = {
                if (pagerState.currentPage < cards.size - 1) {
                    scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
                } else {
                    onComplete()
                }
            },
            modifier = Modifier.fillMaxWidth(),
            shape = WimgShapes.small,
            colors = ButtonDefaults.buttonColors(
                containerColor = WimgColors.accent,
                contentColor = WimgColors.heroText,
            ),
        ) {
            Text(
                if (pagerState.currentPage < cards.size - 1) "Weiter" else "Los geht's",
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }

        Spacer(Modifier.height(16.dp))
    }
}
