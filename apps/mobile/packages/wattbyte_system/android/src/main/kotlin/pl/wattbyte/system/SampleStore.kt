package pl.wattbyte.system

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * Append-only JSON-lines file for samples taken while no Flutter engine runs
 * (the charging worker). Dart drains it on the next refresh.
 */
object SampleStore {
    private val lock = Any()

    private fun file(ctx: Context) = File(ctx.filesDir, "wattbyte_samples.jsonl")

    fun append(ctx: Context, s: BatterySnapshot, source: String) = synchronized(lock) {
        val o = JSONObject()
        o.put("timeMs", s.timeMs)
        o.put("level", s.level)
        o.put("plugged", s.plugged)
        o.put("chargeUah", s.chargeUah ?: JSONObject.NULL)
        o.put("energyNwh", s.energyNwh ?: JSONObject.NULL)
        o.put("voltageMv", s.voltageMv ?: JSONObject.NULL)
        o.put("source", source)
        file(ctx).appendText(o.toString() + "\n")
    }

    fun drain(ctx: Context): List<Map<String, Any?>> = synchronized(lock) {
        val f = file(ctx)
        if (!f.exists()) return emptyList()
        val lines = f.readLines()
        f.delete()
        lines.mapNotNull { line ->
            try {
                val o = JSONObject(line)
                mapOf(
                    "timeMs" to o.getLong("timeMs"),
                    "level" to o.getInt("level"),
                    "plugged" to o.getBoolean("plugged"),
                    "chargeUah" to if (o.isNull("chargeUah")) null else o.getLong("chargeUah"),
                    "energyNwh" to if (o.isNull("energyNwh")) null else o.getLong("energyNwh"),
                    "voltageMv" to if (o.isNull("voltageMv")) null else o.getInt("voltageMv"),
                    "source" to o.optString("source", "worker"),
                )
            } catch (e: Exception) {
                null
            }
        }
    }
}
