package pl.wattbyte.system

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals

class DayRangesTest {
    private val warsaw: TimeZone = TimeZone.getTimeZone("Europe/Warsaw")

    private fun at(y: Int, m: Int, d: Int, h: Int = 0, zone: TimeZone = warsaw): Long =
        Calendar.getInstance(zone, Locale.US).apply {
            clear()
            set(y, m - 1, d, h, 0, 0)
        }.timeInMillis

    @Test
    fun `splits a range into local days and clips the last one`() {
        val ranges = DayRanges.split(at(2026, 10, 12, 15), at(2026, 10, 14, 6), warsaw)
        assertEquals(listOf("2026-10-12", "2026-10-13", "2026-10-14"), ranges.map { it.key })
        assertEquals(at(2026, 10, 12), ranges[0].startMs)
        assertEquals(at(2026, 10, 13), ranges[0].endMs)
        assertEquals(at(2026, 10, 14, 6), ranges[2].endMs)
    }

    @Test
    fun `handles the DST change day (25 hours) without skipping or duplicating days`() {
        // Europe/Warsaw leaves DST on 2026-10-25.
        val ranges = DayRanges.split(at(2026, 10, 24), at(2026, 10, 27), warsaw)
        assertEquals(listOf("2026-10-24", "2026-10-25", "2026-10-26"), ranges.map { it.key })
        assertEquals(25 * 3_600_000L, ranges[1].endMs - ranges[1].startMs)
    }

    @Test
    fun `empty or inverted ranges yield nothing`() {
        assertEquals(emptyList(), DayRanges.split(at(2026, 1, 2), at(2026, 1, 2), warsaw))
        assertEquals(emptyList(), DayRanges.split(at(2026, 1, 3), at(2026, 1, 2), warsaw))
    }
}
