# R8 rules for the release build (Flutter's own rules, flutter_proguard_rules.pro, are added by the Flutter Gradle plugin,
# and every plugin ships its own consumer rules).

# WorkManager stores the worker's class NAME in its database and recreates the worker by reflection, so the class must
# keep its name and constructor; renaming it would orphan the charging-sampler job of an installed app after an update.
-keep class pl.wattbyte.system.ChargingWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}
