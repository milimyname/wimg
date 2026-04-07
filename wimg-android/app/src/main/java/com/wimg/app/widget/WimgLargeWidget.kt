package com.wimg.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.wimg.app.MainActivity
import kotlin.math.abs

private val heroTextFaint = ColorProvider(Color(0x661A1A1A))
private val incomeGreen = ColorProvider(Color(0xCC2D9D55))
private val expenseRed = ColorProvider(Color(0xCCC93636))

class WimgLargeWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = WidgetData.load(context)
        provideContent {
            LargeWidgetContent(data)
        }
    }
}

@Composable
private fun LargeWidgetContent(data: WidgetData) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(widgetBg)
            .padding(16.dp)
            .clickable(actionStartActivity<MainActivity>()),
    ) {
        // Header: available + sparquote
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = "VERFÜGBAR",
                    style = TextStyle(color = heroTextDim, fontSize = 10.sp, fontWeight = FontWeight.Bold),
                )
                Text(
                    text = formatAmountWidget(data.available),
                    style = TextStyle(color = heroText, fontSize = 26.sp, fontWeight = FontWeight.Bold),
                    maxLines = 1,
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "\u25CF",
                    style = TextStyle(color = ColorProvider(sparColor(data.savingsRate)), fontSize = 10.sp),
                )
                Text(
                    text = " Sparquote ${data.savingsRate}%",
                    style = TextStyle(color = heroTextDim, fontSize = 11.sp, fontWeight = FontWeight.Medium),
                )
            }
        }

        Spacer(modifier = GlanceModifier.height(12.dp))

        // Income / Expenses row
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = "EINNAHMEN",
                    style = TextStyle(color = heroTextFaint, fontSize = 9.sp, fontWeight = FontWeight.Bold),
                )
                Text(
                    text = formatAmountWidget(data.income),
                    style = TextStyle(color = incomeGreen, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                    maxLines = 1,
                )
            }
            Spacer(modifier = GlanceModifier.width(16.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = "AUSGABEN",
                    style = TextStyle(color = heroTextFaint, fontSize = 9.sp, fontWeight = FontWeight.Bold),
                )
                Text(
                    text = formatAmountWidget(abs(data.expenses)),
                    style = TextStyle(color = expenseRed, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                    maxLines = 1,
                )
            }
        }

        Spacer(modifier = GlanceModifier.height(12.dp))

        // Recent transactions
        Text(
            text = "LETZTE BUCHUNGEN",
            style = TextStyle(color = heroTextFaint, fontSize = 9.sp, fontWeight = FontWeight.Bold),
        )
        Spacer(modifier = GlanceModifier.height(4.dp))

        if (data.recent.isEmpty()) {
            Text(
                text = if (data.hasData) "Keine Transaktionen" else "Öffne wimg",
                style = TextStyle(color = heroTextFaint, fontSize = 12.sp),
            )
        } else {
            data.recent.take(5).forEach { tx ->
                Row(
                    modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = tx.description,
                        style = TextStyle(color = heroText, fontSize = 12.sp, fontWeight = FontWeight.Medium),
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight(),
                    )
                    Spacer(modifier = GlanceModifier.width(8.dp))
                    Text(
                        text = formatAmountWidget(tx.amount),
                        style = TextStyle(
                            color = if (tx.amount >= 0) incomeGreen else heroText,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

class WimgLargeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WimgLargeWidget()
}
