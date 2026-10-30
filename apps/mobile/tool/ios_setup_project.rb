# Idempotent setup of the iOS Xcode project: bundle ids, entitlements, App Group, privacy
# manifests, the WattByteWidget extension target, the iPhone-only device family, automatic signing
# and the Debug-only local-network Info.plist step.
#
#   LANG=en_US.UTF-8 ruby tool/ios_setup_project.rb      (run from apps/mobile; needs the xcodeproj gem
#                                                         that ships with CocoaPods: `gem list xcodeproj`)
#
# The result is committed in ios/Runner.xcodeproj; the script documents how it was produced and can be
# re-run safely.
#
# Identity (bundle id, App Group) and signing team are NOT written into the project: they come from
# ios/Flutter/WattByte.xcconfig and the optional git-ignored ios/Flutter/Local.xcconfig, so a developer
# can override them without touching tracked files.
require 'xcodeproj'

DEPLOYMENT_TARGET = '15.0'
# v1 ships on iPhone only (docs/PLATFORM_SUPPORT.md); 1 = iPhone, 2 = iPad.
DEVICE_FAMILY = '1'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
tests = project.targets.find { |t| t.name == 'RunnerTests' }
raise 'Runner target missing' unless runner

project.build_configurations.each do |c|
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  c.build_settings['TARGETED_DEVICE_FAMILY'] = DEVICE_FAMILY
end

runner.build_configurations.each do |c|
  # $(WB_BUNDLE_ID) / $(WB_APP_GROUP) are defined in ios/Flutter/WattByte.xcconfig (overridable in Local.xcconfig).
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(WB_BUNDLE_ID)'
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  c.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  c.build_settings.delete('WB_APP_GROUP')
  c.build_settings.delete('TARGETED_DEVICE_FAMILY') # inherited from the project
end
tests&.build_configurations&.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'pl.wattbyte.app.RunnerTests'
  c.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end

def file_in(group, name)
  group.files.find { |f| f.path == name } || group.new_file(name)
end

runner_group = project.main_group['Runner']
file_in(runner_group, 'Runner.entitlements')
privacy_ref = file_in(runner_group, 'PrivacyInfo.xcprivacy')
unless runner.resources_build_phase.files_references.include?(privacy_ref)
  runner.resources_build_phase.add_file_reference(privacy_ref)
end

widget = project.targets.find { |t| t.name == 'WattByteWidget' }
unless widget
  widget = project.new_target(:app_extension, 'WattByteWidget', :ios, DEPLOYMENT_TARGET)
end

wgroup = project.main_group['WattByteWidget'] || project.main_group.new_group('WattByteWidget', 'WattByteWidget')
swift_ref = file_in(wgroup, 'WattByteWidget.swift')
file_in(wgroup, 'Info.plist')
file_in(wgroup, 'WattByteWidget.entitlements')
wprivacy = file_in(wgroup, 'PrivacyInfo.xcprivacy')
widget.add_file_references([swift_ref]) unless widget.source_build_phase.files_references.include?(swift_ref)
widget.resources_build_phase.add_file_reference(wprivacy) unless widget.resources_build_phase.files_references.include?(wprivacy)

# The widget gets its OWN xcconfig chain (ios/Flutter/Widget-Debug.xcconfig, Widget-Release.xcconfig): the same
# Generated/WattByte/Local includes as Runner but NOT the CocoaPods Pods-Runner xcconfig, whose OTHER_LDFLAGS would link every
# Flutter plugin framework into a WidgetKit extension that imports only SwiftUI and WidgetKit (audit H-07).
flutter_group = project.main_group['Flutter']
widget_xcconfigs = %w[Widget-Debug.xcconfig Widget-Release.xcconfig].to_h do |name|
  [name, flutter_group.files.find { |f| f.path == "Flutter/#{name}" } || flutter_group.new_file("Flutter/#{name}")]
end
widget.build_configurations.each do |c|
  s = c.build_settings
  # Debug uses the Debug chain; Profile and Release use the Release chain (as Runner does).
  c.base_configuration_reference = widget_xcconfigs[c.name == 'Debug' ? 'Widget-Debug.xcconfig' : 'Widget-Release.xcconfig']
  s['PRODUCT_BUNDLE_IDENTIFIER'] = '$(WB_BUNDLE_ID).WattByteWidget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'WattByteWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'WattByteWidget/WattByteWidget.entitlements'
  s.delete('WB_APP_GROUP')
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  s['TARGETED_DEVICE_FAMILY'] = DEVICE_FAMILY
  s['SKIP_INSTALL'] = 'YES'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

runner.add_dependency(widget) unless runner.dependencies.any? { |d| d.target == widget }

embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13' # PlugIns
  bf = embed.add_file_reference(widget.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  # Must run before "Thin Binary" or Xcode reports a build cycle.
  phases = runner.build_phases
  phases.delete(embed)
  thin = phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  phases.insert(thin || phases.length, embed)
end

# Debug and Profile builds only: let a physical iPhone reach a LAN development API over plain http
# (NSLocalNetworkUsageDescription + local-networking ATS exception). Runs before Flutter's "Thin Binary"
# phase, which keeps an existing NSLocalNetworkUsageDescription and only appends its own Bonjour entry.
# Release builds are never touched: the script exits before it writes anything.
LOCAL_NETWORK_PHASE = 'WattByte Debug Local Network'
LOCAL_NETWORK_SCRIPT = <<~'SH'
  # Debug/Profile only (see ios/Flutter/WattByte.xcconfig and docs/PLATFORM_SUPPORT.md).
  set -eu
  configuration=$(printf '%s' "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')
  case "${configuration}" in
    *debug*|*profile*) ;;
    *) echo "WattByte: ${CONFIGURATION} build, Info.plist left as is (no local-network keys, no ATS exception)"; exit 0 ;;
  esac
  plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
  if [ ! -f "${plist}" ]; then
    echo "error: ${plist} does not exist; cannot add the development-only local-network keys" >&2
    exit 1
  fi
  /usr/bin/plutil -replace NSLocalNetworkUsageDescription -string "WattByte development builds use the local network to reach a test API and Flutter debugging on your computer. Release builds never ask for this." "${plist}"
  /usr/bin/plutil -replace NSAppTransportSecurity -json '{"NSAllowsLocalNetworking":true}' "${plist}"
  echo "WattByte: ${CONFIGURATION} build, added NSLocalNetworkUsageDescription and NSAllowsLocalNetworking"
SH

local_network = runner.shell_script_build_phases.find { |p| p.name == LOCAL_NETWORK_PHASE }
unless local_network
  local_network = runner.new_shell_script_build_phase(LOCAL_NETWORK_PHASE)
  phases = runner.build_phases
  phases.delete(local_network)
  thin = phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  phases.insert(thin || phases.length, local_network)
end
local_network.shell_script = LOCAL_NETWORK_SCRIPT
local_network.shell_path = '/bin/sh'
local_network.always_out_of_date = '1'
# The built Info.plist must exist before the script edits it (same trick as Flutter's Thin Binary phase).
local_network.input_paths = ['${TARGET_BUILD_DIR}/${INFOPLIST_PATH}']
local_network.output_paths = []

# Xcode's "Automatically manage signing" checkbox reads ProvisioningStyle; the build itself uses CODE_SIGN_STYLE.
attributes = project.root_object.attributes['TargetAttributes'] ||= {}
[runner, widget, tests].compact.each do |t|
  (attributes[t.uuid] ||= {})['ProvisioningStyle'] = 'Automatic'
end

project.save
puts 'ios project updated'
