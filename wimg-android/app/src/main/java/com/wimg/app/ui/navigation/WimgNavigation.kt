package com.wimg.app.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.wimg.app.ui.screens.*

enum class WimgTab(val label: String) {
    DASHBOARD("Home"),
    TRANSACTIONS("Umsätze"),
    MORE("Mehr"),
}

@Composable
fun WimgNavigation() {
    val navController = rememberNavController()
    var selectedTab by remember { mutableStateOf(WimgTab.DASHBOARD) }
    var selectedAccount by remember { mutableStateOf<String?>(null) }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.background,
            ) {
                NavigationBarItem(
                    selected = selectedTab == WimgTab.DASHBOARD,
                    onClick = {
                        selectedTab = WimgTab.DASHBOARD
                        navController.navigate("dashboard") {
                            popUpTo("dashboard") { inclusive = true }
                        }
                    },
                    icon = { Icon(Icons.Filled.Home, contentDescription = "Home") },
                    label = { Text("Home") },
                )
                NavigationBarItem(
                    selected = selectedTab == WimgTab.TRANSACTIONS,
                    onClick = {
                        selectedTab = WimgTab.TRANSACTIONS
                        navController.navigate("transactions") {
                            popUpTo("dashboard")
                        }
                    },
                    icon = { Icon(Icons.AutoMirrored.Filled.List, contentDescription = "Umsätze") },
                    label = { Text("Umsätze") },
                )
                NavigationBarItem(
                    selected = selectedTab == WimgTab.MORE,
                    onClick = {
                        selectedTab = WimgTab.MORE
                        navController.navigate("more") {
                            popUpTo("dashboard")
                        }
                    },
                    icon = { Icon(Icons.Filled.MoreHoriz, contentDescription = "Mehr") },
                    label = { Text("Mehr") },
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = "dashboard",
            modifier = Modifier.padding(padding),
        ) {
            composable("dashboard") { DashboardScreen(selectedAccount = selectedAccount) }
            composable("transactions") { TransactionsScreen(selectedAccount = selectedAccount) }
            composable("more") { MoreScreen(navController = navController) }
            composable("import") { ImportScreen(navController = navController) }
            composable("analysis") { AnalysisScreen(selectedAccount = selectedAccount) }
            composable("debts") { DebtsScreen() }
            composable("goals") { GoalsScreen() }
            composable("recurring") { RecurringScreen() }
            composable("review") { ReviewScreen(selectedAccount = selectedAccount) }
            composable("tax") { TaxScreen() }
            composable("settings") { SettingsScreen() }
            composable("about") { AboutScreen() }
        }
    }
}
