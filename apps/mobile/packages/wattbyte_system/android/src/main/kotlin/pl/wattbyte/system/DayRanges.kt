package pl.wattbyte.system

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/** One local calendar day as a half-open epoch-ms interval plus its `yyyy-MM-dd` key. */
data class DayRange(val key: String, val startMs: Long, val endMs: Long)

/**
 * Pure calendar arithmetic used by [NetworkStatsReader], kept free of Android
 * dependencies so it can be unit-tested on the JVM (DST, month ends, zones).
 */
object DayRanges {
    /** Splits [fromMs, toMs) into local days of [zone]; the last day is clipped to toMs. */
    fun split(fromMs: Long, toMs: Long, zone: TimeZone = TimeZone.getDefault()): List<DayRange> {
        val out = ArrayList<DayRange>()
        if (toMs <= fromMs) return out
        val cal = Calendar.getInstance(zone, Locale.US).apply {
            timeInMillis = fromMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        while (cal.timeInMillis < toMs) {
            val start = cal.timeInMillis
            val key = String.format(
                Locale.US, "%04d-%02d-%02d",
                cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH),
            )
            cal.add(Calendar.DAY_OF_MONTH, 1)
            out.add(DayRange(key, start, minOf(cal.timeInMillis, toMs)))
        }
        return out
    }
}
