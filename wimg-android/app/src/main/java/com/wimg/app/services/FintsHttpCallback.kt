package com.wimg.app.services

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * HTTP callback for FinTS protocol.
 * Called from C via JNI when libwimg needs to make HTTPS requests to bank servers.
 * Must be synchronous — Zig blocks until this returns.
 */
class FintsHttpCallback {
    private val client = OkHttpClient.Builder()
        .connectTimeout(35, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .build()

    /**
     * Called from JNI (wimg_jni.c jni_http_callback).
     * Signature must match: byte[] execute(String url, byte[] body)
     */
    fun execute(url: String, body: ByteArray): ByteArray? {
        return try {
            val request = Request.Builder()
                .url(url)
                .post(body.toRequestBody("text/plain".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.bytes()
            response.close()
            responseBody
        } catch (e: Exception) {
            null
        }
    }
}
