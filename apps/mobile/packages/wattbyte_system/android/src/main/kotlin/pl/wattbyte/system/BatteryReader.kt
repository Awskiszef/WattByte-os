// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

package pl.wattbyte.system

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

data class BatterySnapshot(
    val timeMs: Long,
    /** 0-100, or -1 when unknown. */
    val level: Int,
    val plugged: Boolean,
    /**
     * BATTERY_PROPERTY_CHARGE_COUNTER: the charge currently stored in the battery
     * (microampere-hours), NOT its capacity. Null if unsupported/invalid. Dart only
     * ever turns it into an estimated full-charge capacity, never a design capacity.
     */
    val chargeUah: Long?,
    /** BATTERY_PROPERTY_ENERGY_COUNTER (nanowatt-hours) or null if unsupported/invalid. */
    val energyNwh: Long?,
    /** EXTRA_VOLTAGE (millivolts) or null. */
    val voltageMv: Int?,
) {
    fun toMap(source: String): Map<String, Any?> = mapOf(
        "timeMs" to timeMs,
        "level" to level,
        "plugged" to plugged,
        "chargeUah" to chargeUah,
        "energyNwh" to energyNwh,
        "voltageMv" to voltageMv,
        "source" to source,
    )
}

/** BatteryManager properties plus the sticky ACTION_BATTERY_CHANGED broadcast. */
object BatteryReader {
    fun snapshot(context: Context): BatterySnapshot {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val capacity = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val fallback = if (capacity in 0..100) capacity else -1
        val level = intent?.let {
            BatteryValues.level(
                it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1),
                it.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
                fallback,
            )
        } ?: fallback
        val plugged = (intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        val voltage = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it > 0 }
        return BatterySnapshot(
            timeMs = System.currentTimeMillis(),
            level = level,
            plugged = plugged,
            chargeUah = BatteryValues.counter(bm.getLongProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)),
            energyNwh = BatteryValues.counter(bm.getLongProperty(BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER)),
            voltageMv = voltage,
        )
    }

    fun supports(bm: BatteryManager, id: Int): Boolean = BatteryValues.counter(bm.getLongProperty(id)) != null
}
