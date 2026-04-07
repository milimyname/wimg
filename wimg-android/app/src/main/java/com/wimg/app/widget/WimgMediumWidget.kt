package com.wimg.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.wimg.app.MainActivity
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.abs

private fun formatDate(dateStr: String): String {
    return try {
        val parsed = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(dateStr)
        SimpleDateFormat("d. MMM", Locale.GERMANY).format(parsed!!)
    } catch (_: Exception) { dateStr }
}

class WimgMediumWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = WidgetData.load(context)
        provideContent {
            MediumWidgetContent(data)
        }
    }
}

@Composable
private fun MediumWidgetContent(data: WidgetData) {
    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(widgetBg)
            .padding(16.dp)
            .clickable(actionStartActivity<MainActivity>()),
        verticalAlignment = Alignment.Top,
    ) {
        // Left: available + savings rate
        Column(
            modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
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
                        fontSize = 24.sp,
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

        // Right: next recurring (only if data available)
        if (data.nextMerchant != null && data.nextAmount != null) {
            Spacer(modifier = GlanceModifier.width(16.dp))
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
            ) {
                Text(
                    text = "NÄCHSTE ZAHLUNG",
                    style = TextStyle(
                        color = heroTextDim,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Spacer(modifier = GlanceModifier.height(4.dp))
                Text(
                    text = data.nextMerchant,
                    style = TextStyle(
                        color = heroText,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    maxLines = 1,
                )
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = formatAmountWidget(abs(data.nextAmount)),
                    style = TextStyle(
                        color = heroText,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                if (data.nextDate != null) {
                    Text(
                        text = formatDate(data.nextDate),
                        style = TextStyle(
                            color = heroTextDim,
                            fontSize = 10.sp,
                        ),
                    )
                }
            }
        }
    }
}

class WimgMediumWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WimgMediumWidget()
}
