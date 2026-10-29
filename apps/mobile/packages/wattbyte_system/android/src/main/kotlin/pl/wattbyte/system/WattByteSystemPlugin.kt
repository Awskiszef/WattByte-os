package pl.wattbyte.system

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Method-channel entry point ("wattbyte/system").
 *
 * Registered through GeneratedPluginRegistrant, so it is also available in the
 * background isolate started by WorkManager. Every call maps to an official
 * Android API; see [NetworkStatsReader], [BatteryReader] and [ChargingWorker].
 */
class WattByteSystemPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "wattbyte/system")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
            "queryDataDaily" -> async(result) {
                NetworkStatsReader(context).daily(call.long("fromMs"), call.long("toMs"))
            }
            "queryAppData" -> async(result) {
                NetworkStatsReader(context).byApp(call.long("fromMs"), call.long("toMs"))
            }
            "appGroupId" -> result.success(null) // iOS only
            "deviceInfo" -> result.success(deviceInfo())
            "batterySnapshot" -> result.success(BatteryReader.snapshot(context).toMap("app"))
            "openExternalUrl" -> result.success(openExternalUrl(call.argument<String>("url")))
            "excludeFromBackup" -> result.success(null) // Android: the manifest already excludes the whole app
            "peekSamples" -> result.success(SampleStore.peek(context))
            "ackSamples" -> {
                SampleStore.ack(context, (call.argument<Number>("token") ?: 0).toLong())
                result.success(null)
            }
            "drainSamples" -> result.success(SampleStore.drain(context))
            "ensureChargingWorker" -> {
                ChargingWorker.schedule(context)
                result.success(null)
            }
            "cancelChargingWorker" -> {
                ChargingWorker.cancel(context)
                result.success(null)
            }
            "setChargingNotification" -> {
                ChargingNotifier.configure(
                    context,
                    call.argument<Boolean>("enabled") ?: false,
                    call.argument<String>("title") ?: "",
                    call.argument<String>("body") ?: "",
                    call.argument<String>("channelName") ?: "",
                    call.argument<String>("channelDescription") ?: "",
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun capabilities(): Map<String, Any> {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val state = usageAccessState()
        return mapOf(
            "platform" to "android",
            "dataByApp" to (state != "unavailable"),
            "usageAccess" to (state == "granted"),
            "usageAccessState" to state,
            "chargeCounter" to BatteryReader.supports(bm, BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER),
            "energyCounter" to BatteryReader.supports(bm, BatteryManager.BATTERY_PROPERTY_ENERGY_COUNTER),
            "preciseDataHistory" to (state != "unavailable"),
        )
    }

    /**
     * Public model facts for the automatic setup: Build.MANUFACTURER / MODEL select the
     * entry in the device catalog, the system locale's country picks the default
     * currency. Nothing here identifies the device (no serial, IMEI, MAC or ad id).
     */
    /** Opens an https address in the browser; false for anything else or when nothing can open it. */
    private fun openExternalUrl(url: String?): Boolean {
        val uri = try { android.net.Uri.parse(url ?: return false) } catch (e: Exception) { return false }
        if (uri.scheme != "https" || uri.host.isNullOrEmpty()) return false
        return try {
            context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun deviceInfo(): Map<String, Any?> {
        val locale = context.resources.configuration.locales[0]
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "modelIdentifier" to Build.MODEL,
            "regionCode" to locale.country.takeIf { it.length == 2 },
            "localeTag" to locale.toLanguageTag(),
            "isSimulator" to (Build.FINGERPRINT.contains("generic") || Build.MODEL.contains("sdk_gphone")),
        )
    }

    private val usageSettingsIntent: Intent
        get() = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * `granted` / `denied` / `unavailable`. Unavailable means this device or
     * profile exposes neither the stats service nor the system screen to grant it
     * (some managed profiles and TV/automotive builds), so the UI hides the feature.
     */
    private fun usageAccessState(): String {
        if (context.getSystemService(Context.NETWORK_STATS_SERVICE) == null) return "unavailable"
        if (usageSettingsIntent.resolveActivity(context.packageManager) == null) return "unavailable"
        return if (NetworkStatsReader(context).hasUsageAccess()) "granted" else "denied"
    }

    /** Opens the system "Usage access" screen; false if no activity handles it. */
    private fun openUsageAccessSettings(): Boolean = try {
        context.startActivity(usageSettingsIntent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    /** Runs [block] off the main thread (NetworkStats queries are binder calls). */
    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("native", e.message, e.javaClass.simpleName) }
            }
        }
    }

    private fun MethodCall.long(key: String): Long = (argument<Number>(key) ?: 0L).toLong()
}
