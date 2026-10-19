package pl.wattbyte.system

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class BatteryValuesTest {
    @Test
    fun `unsupported, invalid and unknown counter values become null`() {
        assertNull(BatteryValues.counter(Long.MIN_VALUE)) // unsupported (getLongProperty sentinel)
        assertNull(BatteryValues.counter(0)) // some firmwares report 0 for "not available"
        assertNull(BatteryValues.counter(-120_000)) // negative: invalid
        assertEquals(3_285_000L, BatteryValues.counter(3_285_000))
    }

    @Test
    fun `counter is a current charge measurement, passed through and never reinterpreted as a capacity`() {
        // A half-charged battery stores far less than its capacity; that is still a valid reading
        // and must come back unchanged (Dart extrapolates it into an *estimate* using the level).
        assertEquals(1_650_000L, BatteryValues.counter(1_650_000))
        assertEquals(1L, BatteryValues.counter(1))
    }

    @Test
    fun `level is derived from EXTRA_LEVEL and EXTRA_SCALE and clamped`() {
        assertEquals(50, BatteryValues.level(50, 100, fallback = -1))
        assertEquals(94, BatteryValues.level(94, 100, fallback = -1))
        assertEquals(37, BatteryValues.level(37, -1, fallback = 37)) // bad scale -> fallback
        assertEquals(-1, BatteryValues.level(-1, 100, fallback = -1)) // unknown stays unknown
        assertEquals(100, BatteryValues.level(250, 100, fallback = -1)) // garbage above scale clamps
    }
}
