package com.wimg.app.ui.util

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/// Write [content] to a cache file and open the system share sheet.
/// Used by CSV / DB export from Settings and Search.
fun shareTextFile(context: Context, content: String, filename: String) {
    val file = File(context.cacheDir, filename)
    file.writeText(content)
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val mime = if (filename.endsWith(".json")) "application/json" else "text/csv"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = mime
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "Exportieren"))
}
