package com.wimg.app.services

import android.content.Context
import com.wimg.app.bridge.WimgJni
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

@Serializable
private data class SyncPayload(val rows: List<SyncRow>)

@Serializable
private data class SyncRow(
    val table: String,
    val id: String,
    val data: kotlinx.serialization.json.JsonElement,
    val updated_at: Long,
)

object SyncService {
    private const val BASE_URL = "https://wimg-sync.mili-my.name"
    private const val PREFS = "wimg"
    private const val KEY_SYNC_KEY = "wimg_sync_key"
    private const val KEY_LAST_TS = "wimg_sync_last_ts"

    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private var encryptionKey: ByteArray? = null
    private var webSocket: WebSocket? = null
    private var suppressUntil = 0L

    fun getSyncKey(context: Context): String? {
        return context.getSharedPreferences(PREFS, 0).getString(KEY_SYNC_KEY, null)
    }

    fun isEnabled(context: Context): Boolean = getSyncKey(context) != null

    fun enableSync(context: Context): String {
        val key = java.util.UUID.randomUUID().toString()
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY_SYNC_KEY, key).apply()
        encryptionKey = WimgJni.nativeDeriveKey(key)
        return key
    }

    fun setSyncKey(context: Context, key: String) {
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY_SYNC_KEY, key).apply()
        encryptionKey = WimgJni.nativeDeriveKey(key)
    }

    fun clearSync(context: Context) {
        context.getSharedPreferences(PREFS, 0).edit()
            .remove(KEY_SYNC_KEY)
            .remove(KEY_LAST_TS)
            .apply()
        encryptionKey = null
        webSocket?.close(1000, null)
        webSocket = null
    }

    private fun getLastTs(context: Context): Long {
        return context.getSharedPreferences(PREFS, 0).getLong(KEY_LAST_TS, 0)
    }

    private fun setLastTs(context: Context, ts: Long) {
        context.getSharedPreferences(PREFS, 0).edit().putLong(KEY_LAST_TS, ts).apply()
    }

    suspend fun push(context: Context): Int = withContext(Dispatchers.IO) {
        val syncKey = getSyncKey(context) ?: return@withContext 0
        val lastTs = getLastTs(context)
        val changesJson = WimgJni.nativeGetChanges(lastTs) ?: return@withContext 0

        val key = encryptionKey ?: WimgJni.nativeDeriveKey(syncKey).also { encryptionKey = it } ?: return@withContext 0

        // Encrypt rows
        val payload = json.decodeFromString<SyncPayload>(changesJson)
        if (payload.rows.isEmpty()) return@withContext 0

        val encryptedRows = payload.rows.map { row ->
            val dataStr = row.data.toString()
            val nonce = ByteArray(24).also { SecureRandom().nextBytes(it) }
            val encrypted = WimgJni.nativeEncryptField(dataStr, key, nonce) ?: dataStr
            row.copy(data = kotlinx.serialization.json.JsonPrimitive(encrypted))
        }

        val body = json.encodeToString(SyncPayload.serializer(), SyncPayload(encryptedRows))
        val request = Request.Builder()
            .url("$BASE_URL/sync/$syncKey")
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()

        val response = client.newCall(request).execute()
        if (response.isSuccessful) {
            suppressUntil = System.currentTimeMillis() + 2000
            val maxTs = payload.rows.maxOfOrNull { it.updated_at } ?: lastTs
            if (maxTs > lastTs) setLastTs(context, maxTs)
        }
        response.close()
        payload.rows.size
    }

    suspend fun pull(context: Context): Int = withContext(Dispatchers.IO) {
        val syncKey = getSyncKey(context) ?: return@withContext 0
        val lastTs = getLastTs(context)
        val key = encryptionKey ?: WimgJni.nativeDeriveKey(syncKey).also { encryptionKey = it } ?: return@withContext 0

        val request = Request.Builder()
            .url("$BASE_URL/sync/$syncKey?since=$lastTs")
            .get()
            .build()

        val response = client.newCall(request).execute()
        if (!response.isSuccessful) { response.close(); return@withContext 0 }

        val responseBody = response.body?.string() ?: return@withContext 0
        response.close()

        val payload = json.decodeFromString<SyncPayload>(responseBody)
        if (payload.rows.isEmpty()) return@withContext 0

        // Decrypt rows
        val decryptedRows = payload.rows.map { row ->
            val dataStr = row.data.toString().trim('"')
            val decrypted = WimgJni.nativeDecryptField(dataStr, key)
            if (decrypted != null) {
                row.copy(data = json.parseToJsonElement(decrypted))
            } else {
                row
            }
        }

        val decryptedJson = json.encodeToString(SyncPayload.serializer(), SyncPayload(decryptedRows))
        val applied = WimgJni.nativeApplyChanges(decryptedJson)
        if (applied > 0) {
            val maxTs = payload.rows.maxOfOrNull { it.updated_at } ?: lastTs
            if (maxTs > lastTs) setLastTs(context, maxTs)
            WidgetDataWriter.writeSummary(context)
        }
        applied
    }

    fun connectWebSocket(context: Context, scope: CoroutineScope) {
        val syncKey = getSyncKey(context) ?: return
        val wsUrl = BASE_URL.replace("https://", "wss://").replace("http://", "ws://")

        val request = Request.Builder().url("$wsUrl/ws/$syncKey").build()
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (System.currentTimeMillis() < suppressUntil) return
                scope.launch { pull(context) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                // Auto-reconnect after delay
                scope.launch {
                    delay(5000)
                    connectWebSocket(context, scope)
                }
            }
        })
    }
}
