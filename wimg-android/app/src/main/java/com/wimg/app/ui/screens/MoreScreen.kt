package com.wimg.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController

private data class MoreItem(
    val title: String,
    val icon: ImageVector,
    val color: Color,
    val route: String,
)

@Composable
fun MoreScreen(navController: NavController) {
    val items = listOf(
        MoreItem("Analyse", Icons.Outlined.BarChart, Color(0xFF5856D6), "analysis"),
        MoreItem("Schulden", Icons.Outlined.CreditCard, Color(0xFFFF2D55), "debts"),
        MoreItem("Sparziele", Icons.Outlined.Flag, Color(0xFFFFD60A), "goals"),
        MoreItem("Wiederkehrend", Icons.Outlined.Refresh, Color(0xFF30D158), "recurring"),
        MoreItem("Steuern", Icons.Outlined.Description, Color(0xFFFF9500), "tax"),
        MoreItem("Rückblick", Icons.Outlined.CalendarMonth, Color(0xFFAF52DE), "review"),
        MoreItem("Bankverbindung", Icons.Outlined.AccountBalance, Color(0xFF5AC8FA), "fints"),
        MoreItem("Import", Icons.Outlined.FileUpload, Color(0xFF007AFF), "import"),
        MoreItem("Einstellungen", Icons.Outlined.Settings, Color(0xFF8E8E93), "settings"),
        MoreItem("Feedback", Icons.Outlined.ChatBubbleOutline, Color(0xFF5856D6), "feedback"),
        MoreItem("Über wimg", Icons.Outlined.Info, Color(0xFF8E8E93), "about"),
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(16.dp),
    ) {
        Text(
            "Mehr",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 16.dp),
        )

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(items) { item ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1.4f)
                        .clickable { navController.navigate(item.route) },
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(item.color.copy(alpha = 0.12f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                item.icon,
                                contentDescription = null,
                                tint = item.color,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                        Text(
                            item.title,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            fontSize = 14.sp,
                        )
                    }
                }
            }
        }
    }
}
