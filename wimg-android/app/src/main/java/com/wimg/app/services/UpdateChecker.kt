package com.wimg.app.services

import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL

@Serializable
private data class GitHubRelease(
    val tag_name: String,
    val body: String = "",
)

object UpdateChecker {
    private const val RELEASES_URL = "https://api.github.com/repos/milimyname/wimg/releases/latest"
    private const val DOWNLOAD_URL = "https://github.com/milimyname/wimg/releases/latest/download/wimg.apk"
    private const val CACHE_KEY = "wimg_update_cache"
    private const val CACHE_TS_KEY = "wimg_update_cache_ts"
    private const val CACHE_TTL_MS = 3600_000L // 1 hour

    private val json = Json { ignoreUnknownKeys = true }

    data class UpdateInfo(
        val latestVersion: String,
        val currentVersion: String,
        val hasUpdate: Boolean,
        val releaseNotes: String,
    )

    fun check(context: Context): UpdateInfo? {
        val currentVersion = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: return null
        } catch (_: Exception) {
            return null
        }

        val prefs = context.getSharedPreferences("wimg", 0)

        // Check cache first
        val cachedTs = prefs.getLong(CACHE_TS_KEY, 0)
        val cached = prefs.getString(CACHE_KEY, null)
        if (cached != null && System.currentTimeMillis() - cachedTs < CACHE_TTL_MS) {
            return parseResult(cached, currentVersion)
        }

        // Fetch from GitHub
        return try {
            val conn = URL(RELEASES_URL).openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            conn.connectTimeout = 5000
            conn.readTimeout = 5000

            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().readText()
            conn.disconnect()

            // Cache
            prefs.edit()
                .putString(CACHE_KEY, body)
                .putLong(CACHE_TS_KEY, System.currentTimeMillis())
                .apply()

            parseResult(body, currentVersion)
        } catch (_: Exception) {
            null
        }
    }

    private fun parseResult(jsonStr: String, currentVersion: String): UpdateInfo? {
        return try {
            val release = json.decodeFromString<GitHubRelease>(jsonStr)
            val latest = release.tag_name.removePrefix("v")
            UpdateInfo(
                latestVersion = latest,
                currentVersion = currentVersion,
                hasUpdate = compareVersions(latest, currentVersion) > 0,
                releaseNotes = release.body,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun compareVersions(a: String, b: String): Int {
        val aParts = a.split(".").map { it.toIntOrNull() ?: 0 }
        val bParts = b.split(".").map { it.toIntOrNull() ?: 0 }
        val maxLen = maxOf(aParts.size, bParts.size)
        for (i in 0 until maxLen) {
            val av = aParts.getOrElse(i) { 0 }
            val bv = bParts.getOrElse(i) { 0 }
            if (av != bv) return av.compareTo(bv)
        }
        return 0
    }

    fun openDownload(context: Context) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(DOWNLOAD_URL)))
    }
}
