// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

package pl.wattbyte.system

import android.content.Context
import org.json.JSONObject

/**
 * Append-only JSON-lines file for samples taken while no Flutter engine runs
 * (the charging worker). Dart takes them over in two steps ([peek], then [ack] once they are stored), see [SampleFiles].
 */
object SampleStore {
    private fun files(ctx: Context) = SampleFiles(ctx.filesDir)

    // One SampleFiles per call is fine: its lock must be shared, so keep a single instance per directory.
    private val instances = HashMap<String, SampleFiles>()

    private fun shared(ctx: Context): SampleFiles = synchronized(instances) {
        instances.getOrPut(ctx.filesDir.absolutePath) { files(ctx) }
    }

    fun append(ctx: Context, s: BatterySnapshot, source: String) {
        val o = JSONObject()
        o.put("timeMs", s.timeMs)
        o.put("level", s.level)
        o.put("plugged", s.plugged)
        o.put("chargeUah", s.chargeUah ?: JSONObject.NULL)
        o.put("energyNwh", s.energyNwh ?: JSONObject.NULL)
        o.put("voltageMv", s.voltageMv ?: JSONObject.NULL)
        o.put("source", source)
        shared(ctx).append(o.toString())
    }

    /** `{"token": Long, "samples": [...]}`. The samples stay on disk until [ack] is called with the token. */
    fun peek(ctx: Context): Map<String, Any?> {
        val batch = shared(ctx).peek() ?: return mapOf("token" to 0L, "samples" to emptyList<Map<String, Any?>>())
        return mapOf("token" to batch.token, "samples" to batch.lines.mapNotNull(::decode))
    }

    fun ack(ctx: Context, token: Long) = shared(ctx).ack(token)

    /** The old one-step hand-over, kept for a Dart side that does not know [peek] yet: take and acknowledge at once. */
    fun drain(ctx: Context): List<Map<String, Any?>> {
        val batch = shared(ctx).peek() ?: return emptyList()
        shared(ctx).ack(batch.token)
        return batch.lines.mapNotNull(::decode)
    }

    private fun decode(line: String): Map<String, Any?>? =
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
            null // a torn last line (process killed while appending) is dropped, the rest is kept
        }
}
