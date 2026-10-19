package pl.wattbyte.system

/**
 * Pure value sanitising for BatteryManager readings. No Android imports, so it
 * is unit-tested on the JVM (see android/jvm-tests).
 */
object BatteryValues {
    /**
     * `getLongProperty` returns Long.MIN_VALUE when a property is unsupported;
     * some devices answer 0 or negative numbers for "not available". All of
     * those become null so Dart falls back to an estimate instead of trusting them.
     *
     * A valid value is only a measurement: for BATTERY_PROPERTY_CHARGE_COUNTER it is
     * the charge currently stored in the battery, not the battery's capacity.
     */
    fun counter(raw: Long): Long? = raw.takeIf { it != Long.MIN_VALUE && it > 0 }

    /** Percent from EXTRA_LEVEL / EXTRA_SCALE; [fallback] when the extras are unusable. */
    fun level(level: Int, scale: Int, fallback: Int): Int =
        if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else fallback
}
