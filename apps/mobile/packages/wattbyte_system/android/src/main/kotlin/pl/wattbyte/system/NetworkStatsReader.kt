package pl.wattbyte.system

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.os.Process
import java.io.ByteArrayOutputStream

/**
 * Device and per-app traffic from NetworkStatsManager (public API, API 23+).
 *
 * Needs the PACKAGE_USAGE_STATS special permission, which the user grants in
 * Settings > Usage access. With minSdk 29 the subscriberId may be null and the
 * mobile template then aggregates every SIM.
 */
@Suppress("DEPRECATION") // ConnectivityManager.TYPE_* are what NetworkStatsManager takes.
class NetworkStatsReader(private val context: Context) {
    private val nsm = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager

    fun hasUsageAccess(): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** One map per local calendar day in [fromMs, toMs). */
    fun daily(fromMs: Long, toMs: Long): List<Map<String, Any>> =
        DayRanges.split(fromMs, toMs).map { day ->
            val mobile = summary(ConnectivityManager.TYPE_MOBILE, day.startMs, day.endMs)
            val wifi = summary(ConnectivityManager.TYPE_WIFI, day.startMs, day.endMs)
            mapOf(
                "day" to day.key,
                "mobileRx" to mobile.rxBytes,
                "mobileTx" to mobile.txBytes,
                "wifiRx" to wifi.rxBytes,
                "wifiTx" to wifi.txBytes,
            )
        }

    private fun summary(type: Int, start: Long, end: Long): NetworkStats.Bucket =
        nsm.querySummaryForDevice(type, null, start, end) ?: NetworkStats.Bucket()

    /** Per-uid totals in [fromMs, toMs), largest first; special uids merged by kind. */
    fun byApp(fromMs: Long, toMs: Long): List<Map<String, Any?>> {
        val totals = HashMap<Int, LongArray>()
        fun accumulate(type: Int, idx: Int) {
            val stats = nsm.querySummary(type, null, fromMs, toMs) ?: return
            val b = NetworkStats.Bucket()
            while (stats.hasNextBucket()) {
                stats.getNextBucket(b)
                totals.getOrPut(b.uid) { LongArray(2) }[idx] += b.rxBytes + b.txBytes
            }
            stats.close()
        }
        accumulate(ConnectivityManager.TYPE_MOBILE, 0)
        accumulate(ConnectivityManager.TYPE_WIFI, 1)

        val pm = context.packageManager
        val rows = totals.entries.map { (uid, t) ->
            resolve(pm, uid) + mapOf("uid" to uid, "mobile" to t[0], "wifi" to t[1])
        }
        val apps = rows.filter { it["kind"] == "app" }
        val merged = rows.filter { it["kind"] != "app" }
            .groupBy { it["kind"] as String }
            .map { (kind, list) ->
                special(kind) + mapOf(
                    "uid" to -1,
                    "mobile" to list.sumOf { it["mobile"] as Long },
                    "wifi" to list.sumOf { it["wifi"] as Long },
                )
            }
        return (apps + merged).sortedByDescending { (it["mobile"] as Long) + (it["wifi"] as Long) }
    }

    private fun resolve(pm: PackageManager, uid: Int): Map<String, Any?> {
        when (uid) {
            NetworkStats.Bucket.UID_REMOVED -> return special("removed")
            NetworkStats.Bucket.UID_TETHERING -> return special("tethering")
            Process.SYSTEM_UID -> return special("system")
        }
        // Only packages visible through the manifest <queries> resolve here.
        val pkg = try {
            pm.getPackagesForUid(uid)?.firstOrNull()
        } catch (e: SecurityException) {
            null
        } ?: return special("unknown")
        return try {
            val info = pm.getApplicationInfo(pkg, 0)
            mapOf(
                "kind" to "app",
                "name" to pm.getApplicationLabel(info).toString(),
                "package" to pkg,
                "icon" to cachedIcon(pm, pkg) { pm.getApplicationIcon(info) },
            )
        } catch (e: PackageManager.NameNotFoundException) {
            special("unknown")
        }
    }

    /** Icons are rendered once per package and kept for the process lifetime. */
    private fun cachedIcon(pm: PackageManager, pkg: String, load: () -> Drawable): ByteArray? =
        synchronized(iconCache) {
            if (iconCache.containsKey(pkg)) return iconCache[pkg]
            if (iconCache.size >= ICON_CACHE_MAX) iconCache.clear() // ponytail: full flush, LRU if it matters
            val bytes = iconBytes(load())
            iconCache[pkg] = bytes
            bytes
        }

    private companion object {
        const val ICON_CACHE_MAX = 400
        val iconCache = HashMap<String, ByteArray?>()
    }

    private fun special(kind: String): Map<String, Any?> =
        mapOf("kind" to kind, "name" to "", "package" to null, "icon" to null)

    private fun iconBytes(d: Drawable): ByteArray? = try {
        val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, 96, 96)
        d.draw(Canvas(bmp))
        ByteArrayOutputStream().use {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    } catch (e: Exception) {
        null
    }
}
