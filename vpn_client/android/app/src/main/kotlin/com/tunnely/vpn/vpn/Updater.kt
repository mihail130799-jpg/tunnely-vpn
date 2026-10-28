package com.tunnely.vpn.vpn

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/** Installs an update APK that the Flutter side downloaded and hash-checked. */
object Updater {
    private const val AUTHORITY = "com.tunnely.vpn.fileprovider"

    fun appInfo(activity: Activity): Map<String, String> {
        val pi = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return mapOf(
            "version" to (pi.versionName ?: ""),
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
        )
    }

    /**
     * Returns "started" when the system installer was opened, or "permission" when
     * the user first has to allow installing from Tunnely (settings screen opened).
     * The APK must be inside cacheDir/updates (see res/xml/file_paths.xml).
     */
    fun install(activity: Activity, path: String): String {
        val file = File(path).canonicalFile
        val updates = File(activity.cacheDir, "updates").canonicalFile
        require(file.parentFile == updates && file.name.endsWith(".apk")) { "unexpected path" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
            )
            return "permission"
        }
        val uri = FileProvider.getUriForFile(activity, AUTHORITY, file)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return "started"
    }
}
