package com.wimg.app.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.wimg.app.ui.screens.*

private const val ONBOARDING_KEY = "wimg_onboarding_done"

@Composable
fun WimgNavigation() {
    val context = LocalContext.current
    val prefs = context.getSharedPreferences("wimg", 0)
    var onboardingDone by remember { mutableStateOf(prefs.getBoolean(ONBOARDING_KEY, false)) }

    if (!onboardingDone) {
        OnboardingScreen(onComplete = {
            prefs.edit().putBoolean(ONBOARDING_KEY, true).apply()
            onboardingDone = true
        })
        return
    }

    val navController = rememberNavController()
    var selectedTab by remember { mutableIntStateOf(1) }
    var selectedAccount by remember { mutableStateOf<String?>(null) }

    Scaffold(
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.background,
            ) {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = {
                        selectedTab = 0
                        navController.navigate("search") { popUpTo("dashboard") }
                    },
                    icon = { Icon(Icons.Outlined.Search, contentDescription = "Suche") },
                    label = { Text("Suche") },
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = {
                        selectedTab = 1
                        navController.navigate("dashboard") { popUpTo("dashboard") { inclusive = true } }
                    },
                    icon = { Icon(Icons.Filled.Home, contentDescription = "Home") },
                    label = { Text("Home") },
                )
                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = {
                        selectedTab = 2
                        navController.navigate("transactions") { popUpTo("dashboard") }
                    },
                    icon = { Icon(Icons.AutoMirrored.Filled.List, contentDescription = "Umsätze") },
                    label = { Text("Umsätze") },
                )
                NavigationBarItem(
                    selected = selectedTab == 3,
                    onClick = {
                        selectedTab = 3
                        navController.navigate("more") { popUpTo("dashboard") }
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
            composable("search") { SearchScreen(selectedAccount = selectedAccount) }
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
