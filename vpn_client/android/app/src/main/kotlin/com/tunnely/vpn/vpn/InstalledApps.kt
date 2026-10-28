package com.tunnely.vpn.vpn

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream

/** Apps the user can see in the launcher (visible thanks to the LAUNCHER <queries> entry). */
object InstalledApps {
    private fun launcherApps(context: Context) =
        context.packageManager.queryIntentActivities(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0,
        ).map { it.activityInfo.applicationInfo }
            .distinctBy { it.packageName }
            .filter { it.packageName != context.packageName }

    /** Package names only (fast; used on every connect). */
    fun packages(context: Context): List<String> = launcherApps(context).map { it.packageName }

    /** Package, label, system flag and a small PNG icon for the app picker. */
    fun withIcons(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        return launcherApps(context).map { info ->
            mapOf(
                "package" to info.packageName,
                "label" to pm.getApplicationLabel(info).toString(),
                "system" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                "icon" to iconPng(context, info),
            )
        }.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun iconPng(context: Context, info: ApplicationInfo): ByteArray? = try {
        val d = context.packageManager.getApplicationIcon(info)
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bmp))
        ByteArrayOutputStream().use {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    } catch (_: Exception) {
        null
    }
}
