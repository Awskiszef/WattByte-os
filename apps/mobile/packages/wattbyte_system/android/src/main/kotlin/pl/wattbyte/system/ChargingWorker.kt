package pl.wattbyte.system

import android.content.Context
import android.os.SystemClock
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Samples the battery once a minute while the device charges.
 *
 * ACTION_POWER_CONNECTED cannot wake a manifest receiver since Android 8, so
 * the sanctioned path is a WorkManager job with the "requires charging"
 * constraint: the system starts it when a charger is connected and stops it
 * ([isStopped]) when the charger is removed. Each run ends before the 10-minute
 * job limit and appends the next run, so one long charge is a chain of jobs.
 */
class ChargingWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    override fun doWork(): Result =
        try {
            sampleWhileCharging()
        } catch (e: Throwable) {
            // Any failure (a sensor read, a full disk, the notifier) used to end the job as FAILED and with it the whole
            // chain: no next job was queued until the user opened the app (H-10). Keep sampling: queue the next job, a
            // little later so a persistent failure cannot spin, and let this one end normally.
            if (!isStopped) {
                try {
                    schedule(applicationContext, append = true, delayMs = ERROR_BACKOFF_MS)
                } catch (_: Throwable) {
                    // WorkManager itself refused: nothing more can be done from here, the app re-arms the chain on open.
                }
            }
            Result.success()
        }

    private fun sampleWhileCharging(): Result {
        val ctx = applicationContext
        val deadline = SystemClock.elapsedRealtime() + RUN_LIMIT_MS
        var snap = BatteryReader.snapshot(ctx)
        SampleStore.append(ctx, snap, SOURCE)
        ChargingNotifier.onSample(ctx, snap.plugged, snap.timeMs)
        while (!isStopped && snap.plugged && SystemClock.elapsedRealtime() < deadline) {
            sleepUnlessStopped(SAMPLE_MS)
            if (isStopped) break
            snap = BatteryReader.snapshot(ctx)
            SampleStore.append(ctx, snap, SOURCE)
            ChargingNotifier.onSample(ctx, snap.plugged, snap.timeMs)
        }
        // Stopped by the system: WorkManager re-enqueues the work itself and
        // onStopped() has recorded the end state.
        if (isStopped) return Result.success()
        if (!snap.plugged) ChargingNotifier.sessionCompleted(ctx)
        schedule(ctx, append = true)
        return Result.success()
    }

    override fun onStopped() {
        // Runs on a system thread when the job is stopped: an exception here must not take the process down.
        try {
            val ctx = applicationContext
            val snap = BatteryReader.snapshot(ctx)
            SampleStore.append(ctx, snap, SOURCE)
            if (!snap.plugged) ChargingNotifier.sessionCompleted(ctx)
        } catch (_: Throwable) {
            // The next job (re-enqueued by WorkManager) takes a fresh sample.
        }
    }

    private fun sleepUnlessStopped(ms: Long) {
        val end = SystemClock.elapsedRealtime() + ms
        while (!isStopped && SystemClock.elapsedRealtime() < end) Thread.sleep(1000)
    }

    companion object {
        const val WORK = "wattbyte.charging"
        const val SOURCE = "worker"
        const val SAMPLE_MS = 60_000L
        const val RUN_LIMIT_MS = 9 * 60_000L

        /** Wait before the next job after a failed run, so a failure that repeats cannot become a busy loop. */
        const val ERROR_BACKOFF_MS = 5 * 60_000L

        /** Stops sampling for good (the user turned data collection off). */
        fun cancel(ctx: Context) {
            WorkManager.getInstance(ctx).cancelUniqueWork(WORK)
        }

        fun schedule(ctx: Context, append: Boolean = false, delayMs: Long = 0L) {
            val builder = OneTimeWorkRequestBuilder<ChargingWorker>()
                .setConstraints(Constraints.Builder().setRequiresCharging(true).build())
            if (delayMs > 0) builder.setInitialDelay(delayMs, java.util.concurrent.TimeUnit.MILLISECONDS)
            val request = builder.build()
            WorkManager.getInstance(ctx).enqueueUniqueWork(
                WORK,
                if (append) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }
}
