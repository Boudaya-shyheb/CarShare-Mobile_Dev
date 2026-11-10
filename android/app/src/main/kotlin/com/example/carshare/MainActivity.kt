package com.example.carshare

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.database.Cursor
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val SUPPORT_DOCUMENT_PICKER_CHANNEL = "carshare.support/document_picker"
        const val SUPPORT_DOCUMENT_PICKER_REQUEST = 4917
        const val SUPPORT_DOCUMENT_MIME_TYPE = "application/*"
    }

    private var pendingSupportDocumentResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SUPPORT_DOCUMENT_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "pickDocument") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingSupportDocumentResult != null) {
                result.error("picker_busy", "A document picker is already open.", null)
                return@setMethodCallHandler
            }

            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = SUPPORT_DOCUMENT_MIME_TYPE
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/pdf",
                        "application/msword",
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        "text/plain",
                        "application/rtf",
                        "application/vnd.oasis.opendocument.text",
                    ),
                )
            }

            try {
                pendingSupportDocumentResult = result
                startActivityForResult(intent, SUPPORT_DOCUMENT_PICKER_REQUEST)
            } catch (error: ActivityNotFoundException) {
                pendingSupportDocumentResult = null
                result.error(
                    "picker_unavailable",
                    "No document picker is available on this device.",
                    null,
                )
            } catch (error: SecurityException) {
                pendingSupportDocumentResult = null
                result.error("picker_unavailable", "The document picker could not be opened.", null)
            }
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SUPPORT_DOCUMENT_PICKER_REQUEST) return

        val result = pendingSupportDocumentResult ?: return
        pendingSupportDocumentResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("invalid_picker_result", "No document was selected.", null)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            val name = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            ).use { cursor: Cursor? ->
                if (cursor != null && cursor.moveToFirst()) {
                    cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))
                } else {
                    null
                }
            } ?: uri.lastPathSegment ?: "Selected document"

            result.success(mapOf("name" to name, "uri" to uri.toString()))
        } catch (error: Exception) {
            result.error("document_read_failed", "The selected document could not be accessed.", null)
        }
    }
}
