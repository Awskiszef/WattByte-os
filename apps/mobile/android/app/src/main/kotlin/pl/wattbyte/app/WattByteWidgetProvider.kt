// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

package pl.wattbyte.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Renders the strings Dart publishes through home_widget. Layout is picked from
 * the widget's current size so one provider serves small, medium and large.
 */
class WattByteWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int, data: SharedPreferences) {
        val options = manager.getAppWidgetOptions(id)
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        val keys: List<Pair<Int, String>>
        val layout: Int
        when {
            height >= 180 && width >= 180 -> {
                layout = R.layout.widget_large
                keys = listOf(
                    R.id.label_data_today to "label_data_today", R.id.data_today to "data_today",
                    R.id.label_energy_today to "label_energy_today", R.id.energy_today to "energy_today",
                    R.id.label_data_month to "label_data_month", R.id.data_month to "data_month",
                    R.id.label_cost_month to "label_cost_month", R.id.cost_month to "cost_month",
                )
            }
            width >= 180 -> {
                layout = R.layout.widget_medium
                keys = listOf(
                    R.id.label_data to "label_data", R.id.data_today to "data_today",
                    R.id.label_energy to "label_energy", R.id.energy_today to "energy_today",
                    R.id.label_cost to "label_cost", R.id.cost_today to "cost_today",
                )
            }
            else -> {
                layout = R.layout.widget_small
                keys = listOf(R.id.label_data_today to "label_data_today", R.id.data_today to "data_today")
            }
        }
        val views = RemoteViews(context.packageName, layout)
        for ((viewId, key) in keys) views.setTextViewText(viewId, data.getString(key, "—") ?: "—")
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
            views.setOnClickPendingIntent(
                R.id.root,
                PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )
        }
        manager.updateAppWidget(id, views)
    }
}
