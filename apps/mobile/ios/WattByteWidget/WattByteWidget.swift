import SwiftUI
import WidgetKit

// Home-screen widget. Reads the localized strings the app publishes through
// home_widget into the shared App Group (the App Group).
//
// The target, entitlements and App Group are configured in ios/Runner.xcodeproj
// (see tool/ios_setup_project.rb).

/// The App Group id is a build setting (WB_APP_GROUP) exposed through Info.plist, so the
/// app, the widget and the entitlements always agree. No literal is repeated in code.
private let appGroup: String = Bundle.main.object(forInfoDictionaryKey: "WBAppGroup") as? String ?? ""

struct WattByteEntry: TimelineEntry {
  let date: Date
  let values: [String: String]

  func value(_ key: String, fallback: String = "—") -> String {
    values[key] ?? fallback
  }

  static let placeholder = WattByteEntry(
    date: Date(),
    values: [
      "label_data_today": "Data today", "data_today": "8.4 GB",
      "label_energy_today": "Energy today", "energy_today": "~0.011 kWh",
      "label_cost_today": "Cost today", "cost_today": "~0.013 PLN",
      "label_data_month": "Monthly data", "data_month": "112 GB",
      "label_cost_month": "Monthly cost", "cost_month": "~0.41 PLN",
      "label_data": "Data", "label_energy": "Energy", "label_cost": "Cost",
    ])
}

struct WattByteProvider: TimelineProvider {
  private let keys = [
    "data_today", "energy_today", "cost_today", "data_month", "cost_month",
    "label_data_today", "label_energy_today", "label_cost_today",
    "label_data_month", "label_cost_month", "label_data", "label_energy", "label_cost",
  ]

  func placeholder(in context: Context) -> WattByteEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (WattByteEntry) -> Void) {
    completion(context.isPreview ? .placeholder : load())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WattByteEntry>) -> Void) {
    completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(30 * 60))))
  }

  private func load() -> WattByteEntry {
    let defaults = appGroup.isEmpty ? nil : UserDefaults(suiteName: appGroup)
    var values: [String: String] = [:]
    for key in keys {
      if let v = defaults?.string(forKey: key) { values[key] = v }
    }
    return WattByteEntry(date: Date(), values: values)
  }
}

private struct Stat: View {
  let label: String
  let value: String
  var accent: Color = .primary
  var size: CGFloat = 22

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.system(size: size, weight: .bold, design: .rounded))
        .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.5)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct WattByteWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: WattByteEntry

  private let bolt = Color(red: 1.0, green: 0.77, blue: 0.24)

  var body: some View {
    Group {
      switch family {
      case .systemMedium:
        HStack(alignment: .top, spacing: 12) {
          Stat(label: entry.value("label_data"), value: entry.value("data_today"), size: 18)
          Stat(label: entry.value("label_energy"), value: entry.value("energy_today"), accent: bolt, size: 18)
          Stat(label: entry.value("label_cost"), value: entry.value("cost_today"), size: 18)
        }
      case .systemLarge:
        VStack(alignment: .leading, spacing: 18) {
          header
          HStack(spacing: 12) {
            Stat(label: entry.value("label_data_today"), value: entry.value("data_today"), size: 26)
            Stat(label: entry.value("label_energy_today"), value: entry.value("energy_today"), accent: bolt, size: 26)
          }
          HStack(spacing: 12) {
            Stat(label: entry.value("label_data_month"), value: entry.value("data_month"), size: 26)
            Stat(label: entry.value("label_cost_month"), value: entry.value("cost_month"), size: 26)
          }
          Spacer(minLength: 0)
        }
      default:
        VStack(alignment: .leading, spacing: 8) {
          header
          Spacer(minLength: 0)
          Stat(label: entry.value("label_data_today"), value: entry.value("data_today"), size: 26)
        }
      }
    }
    .padding(family == .systemSmall ? 14 : 16)
    .widgetBackground()
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: "bolt.fill").foregroundStyle(bolt)
      Text("WattByte").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
  }
}

private extension View {
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(for: .widget) { Color(.systemBackground) }
    } else {
      background(Color(.systemBackground))
    }
  }
}

@main
struct WattByteWidget: Widget {
  let kind = "WattByteWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WattByteProvider()) { entry in
      WattByteWidgetView(entry: entry)
    }
    .configurationDisplayName("WattByte")
    .description("Data and energy at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
