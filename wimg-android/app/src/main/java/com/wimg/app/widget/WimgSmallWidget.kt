package com.wimg.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.wimg.app.MainActivity
import java.text.NumberFormat
import java.util.Locale

internal val widgetBg = Color(0xFFFFE97D)
internal val heroText = ColorProvider(Color(0xFF1A1A1A))
internal val heroTextDim = ColorProvider(Color(0x991A1A1A))

internal fun formatAmountWidget(value: Double): String {
    val formatter = NumberFormat.getNumberInstance(Locale.GERMANY)
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.format(value) + " \u20AC"
}

class WimgSmallWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = WidgetData.load(context)
        provideContent {
            SmallWidgetContent(data)
        }
    }
}

@Composable
private fun SmallWidgetContent(data: WidgetData) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(widgetBg)
            .padding(16.dp)
            .clickable(actionStartActivity<MainActivity>()),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = "VERFÜGBAR",
            style = TextStyle(
                color = heroTextDim,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
        Spacer(modifier = GlanceModifier.height(4.dp))
        if (data.hasData) {
            Text(
                text = formatAmountWidget(data.available),
                style = TextStyle(
                    color = heroText,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
            Spacer(modifier = GlanceModifier.defaultWeight())
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "\u25CF",
                    style = TextStyle(
                        color = ColorProvider(sparColor(data.savingsRate)),
                        fontSize = 10.sp,
                    ),
                )
                Text(
                    text = " Sparquote ${data.savingsRate}%",
                    style = TextStyle(
                        color = heroTextDim,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            }
        } else {
            Spacer(modifier = GlanceModifier.defaultWeight())
            Text(
                text = "Öffne wimg",
                style = TextStyle(color = heroTextDim, fontSize = 12.sp),
            )
        }
    }
}

internal fun sparColor(rate: Int): Color = when {
    rate >= 20 -> Color(0xFF34C759)
    rate >= 0 -> Color(0xFFFF9500)
    else -> Color(0xFFFF3B30)
}

class WimgSmallWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WimgSmallWidget()
}
