// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'plist.dart';

/// The native projects, read as files (the tests run from `apps/mobile`).
///
/// These are regression tests of CONFIGURATION, not of behaviour: they catch the
/// day someone re-adds the literal `ARCHS` line, drops the scene manifest, ships
/// an App Transport Security exception in the release plist, turns Android
/// backups on, or commits a signing key. What they cannot show is that the app
/// builds or runs: that is the job of `flutter build` and the simulator
/// (`docs/PLATFORM_SUPPORT.md`).
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// The text without XML comments (the manifests explain themselves in
  /// comments that mention the very attributes they forbid).
  String stripXmlComments(String s) =>
      s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  /// Swift/xcconfig/Ruby comments out, so a commented-out old line is not a hit.
  String stripLineComments(String s) =>
      s.split('\n').where((l) => !RegExp(r'^\s*(//|#)').hasMatch(l)).join('\n');

  // `ARCHS[sdk=iphonesimulator*] = arm64`, quoted or not, in xcconfig, Ruby
  // (`config.build_settings['ARCHS[sdk=iphonesimulator*]'] = 'arm64'`) or pbxproj
  // (`"ARCHS[sdk=iphonesimulator*]" = arm64;`) syntax.
  final literal = RegExp(
      r'''ARCHS\[sdk=iphonesimulator\*\]['"]?\]?\s*=\s*\n?\s*['"]?(arm64|x86_64|arm64e)['"]?\s*;?\s*$''',
      multiLine: true);
  final excludesX86 = RegExp(
      r'''EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]['"]?\]?\s*=\s*['"]?(\$\(inherited\)\s+)?x86_64''');

  group('iOS: UIScene lifecycle (bug 1, iOS 27 refuses to launch without it)',
      () {
    final info = parsePlistDict(read('ios/Runner/Info.plist'));

    test('Info.plist has a UIApplicationSceneManifest with one window scene',
        () {
      final manifest = info['UIApplicationSceneManifest'];
      expect(manifest, isA<Map<String, Object?>>());
      manifest as Map<String, Object?>;
      expect(manifest['UIApplicationSupportsMultipleScenes'], false);
      final configs = manifest['UISceneConfigurations'] as Map<String, Object?>;
      final roles = configs['UIWindowSceneSessionRoleApplication'] as List;
      expect(roles, hasLength(1));
      final scene = roles.single as Map<String, Object?>;
      expect(scene['UISceneClassName'], 'UIWindowScene');
      expect(scene['UISceneConfigurationName'], isNotEmpty);
      expect(scene['UISceneDelegateClassName'],
          r'$(PRODUCT_MODULE_NAME).SceneDelegate');
      expect(scene['UISceneStoryboardFile'], 'Main');
      expect(File('ios/Runner/Base.lproj/Main.storyboard').existsSync(), isTrue,
          reason: 'the scene refers to the Main storyboard');
    });

    test('SceneDelegate subclasses FlutterSceneDelegate', () {
      final swift = stripLineComments(read('ios/Runner/SceneDelegate.swift'));
      expect(swift, contains('import Flutter'));
      expect(swift,
          matches(RegExp(r'class\s+SceneDelegate\s*:\s*FlutterSceneDelegate')));
    });

    test(
        'AppDelegate adopts FlutterImplicitEngineDelegate and registers the '
        'plugins on the implicit engine', () {
      final swift = stripLineComments(read('ios/Runner/AppDelegate.swift'));
      expect(
          swift,
          matches(RegExp(
              r'class\s+AppDelegate\s*:\s*FlutterAppDelegate\s*,\s*FlutterImplicitEngineDelegate')));
      expect(swift, contains('didInitializeImplicitFlutterEngine'));
      expect(swift, contains('FlutterImplicitEngineBridge'));
      expect(
          swift,
          contains(
              'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)'));
      // The pre-scene pattern registers on `self` in didFinishLaunching.
      expect(swift,
          isNot(contains('GeneratedPluginRegistrant.register(with: self)')));
      // The single @main entry point.
      expect(
          RegExp(r'^@main', multiLine: true).allMatches(swift), hasLength(1));
    });

    test(
        'the background-task identifier is the same in Dart, Swift and the plist',
        () {
      final dart = RegExp(r'''const kRefreshTask\s*=\s*'([^']+)';''')
          .firstMatch(read('lib/background/background_tasks.dart'))
          ?.group(1);
      expect(dart, isNotNull);
      final swift = read('ios/Runner/AppDelegate.swift');
      expect(swift, contains('withIdentifier: "$dart"'));
      expect(info['BGTaskSchedulerPermittedIdentifiers'], [dart]);
    });
  });

  group('iOS: the widget extension links no Flutter plugin (audit H-07)', () {
    final pbxproj = read('ios/Runner.xcodeproj/project.pbxproj');

    /// `#include` / `#include?` targets of an xcconfig, comments ignored.
    List<String> includes(String path) => RegExp(r'^\s*#include\??\s+"([^"]+)"',
            multiLine: true)
        // `#include` starts with '#', so only the `//` comments may be dropped here.
        .allMatches(read(path)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n'))
        .map((m) => m.group(1)!)
        .toList();

    /// All includes reachable from [path], following the files that live in ios/Flutter.
    Set<String> chain(String path, [Set<String>? seen]) {
      seen ??= {};
      for (final inc in includes(path)) {
        if (seen.add(inc) && File('ios/Flutter/$inc').existsSync()) {
          chain('ios/Flutter/$inc', seen);
        }
      }
      return seen;
    }

    /// The `baseConfigurationReference` name of each configuration of the widget target.
    Map<String, String> widgetBases() {
      final list = RegExp(
              r'buildConfigurationList = (\w+) /\* Build configuration list for PBXNativeTarget "WattByteWidget" \*/')
          .firstMatch(pbxproj)!
          .group(1)!;
      final listBlock = RegExp(
              '$list /\\* Build configuration list for PBXNativeTarget "WattByteWidget" \\*/ = \\{[\\s\\S]*?\\};')
          .firstMatch(pbxproj)!
          .group(0)!;
      final out = <String, String>{};
      for (final m
          in RegExp(r'(\w{24}) /\* (\w+) \*/,').allMatches(listBlock)) {
        final cfg = RegExp(
                '${m.group(1)} /\\* ${m.group(2)} \\*/ = \\{\\s*isa = XCBuildConfiguration;\\s*baseConfigurationReference = \\w+ /\\* ([\\w.\\-]+) \\*/;')
            .firstMatch(pbxproj)!;
        out[m.group(2)!] = cfg.group(1)!;
      }
      return out;
    }

    test(
        'every widget configuration has a base xcconfig of its own, not Runner\'s',
        () {
      expect(widgetBases(), {
        'Debug': 'Widget-Debug.xcconfig',
        'Release': 'Widget-Release.xcconfig',
        'Profile': 'Widget-Release.xcconfig',
      });
    });

    test('and nothing it includes, directly or not, pulls in CocoaPods', () {
      for (final f in ['Widget-Debug.xcconfig', 'Widget-Release.xcconfig']) {
        final reachable = chain('ios/Flutter/$f');
        expect(
            reachable, containsAll(['Generated.xcconfig', 'WattByte.xcconfig']),
            reason: '$f still gets the version numbers and the identity');
        expect(reachable.where((i) => i.contains('Pods')), isEmpty,
            reason:
                '$f must not include a Pods xcconfig (OTHER_LDFLAGS would link every plugin)');
      }
    });

    test('Runner still gets the Pods xcconfig (the check above can fail)', () {
      expect(
          chain('ios/Flutter/Debug.xcconfig')
              .any((i) => i.contains('Pods-Runner')),
          isTrue);
      expect(
          chain('ios/Flutter/Release.xcconfig')
              .any((i) => i.contains('Pods-Runner')),
          isTrue);
    });

    test('the setup script produces the same arrangement', () {
      final rb = read('tool/ios_setup_project.rb');
      expect(rb, contains('Widget-Debug.xcconfig'));
      expect(rb, contains('Widget-Release.xcconfig'));
      expect(
          stripLineComments(rb), isNot(contains('runner_xcconfigs[c.name]')));
    });
  });

  group('iOS: simulator architectures (bug 2, Xcode 27 lipo -verify_arch)', () {
    final files = <String, String>{
      'ios/Podfile': read('ios/Podfile'),
      'ios/Flutter/WattByte.xcconfig': read('ios/Flutter/WattByte.xcconfig'),
      'ios/Flutter/Debug.xcconfig': read('ios/Flutter/Debug.xcconfig'),
      'ios/Flutter/Release.xcconfig': read('ios/Flutter/Release.xcconfig'),
      'ios/Runner.xcodeproj/project.pbxproj':
          read('ios/Runner.xcodeproj/project.pbxproj'),
      // Generated by `pod install` from the Podfile; absent on a fresh checkout.
      if (File('ios/Pods/Pods.xcodeproj/project.pbxproj').existsSync())
        'ios/Pods/Pods.xcodeproj/project.pbxproj':
            read('ios/Pods/Pods.xcodeproj/project.pbxproj'),
    };

    test('the detectors do detect the old literal lines (they can fail)', () {
      for (final bad in [
        'ARCHS[sdk=iphonesimulator*] = arm64',
        'ARCHS[sdk=iphonesimulator*]=x86_64',
        "config.build_settings['ARCHS[sdk=iphonesimulator*]'] = 'arm64'",
        '"ARCHS[sdk=iphonesimulator*]" = arm64;',
        "config.build_settings['ARCHS[sdk=iphonesimulator*]'] =\n        'arm64'",
      ]) {
        expect(literal.hasMatch(bad), isTrue, reason: bad);
      }
      for (final bad in [
        'EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64',
        'EXCLUDED_ARCHS[sdk=iphonesimulator*] = \$(inherited) x86_64',
      ]) {
        expect(excludesX86.hasMatch(bad), isTrue, reason: bad);
      }
      for (final good in [
        r'ARCHS[sdk=iphonesimulator*] = $(WB_SIM_ARCH_FOR_$(NATIVE_ARCH_ACTUAL):default=$(ARCHS_STANDARD))',
        'EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386',
      ]) {
        expect(literal.hasMatch(good), isFalse, reason: good);
        expect(excludesX86.hasMatch(good), isFalse, reason: good);
      }
    });

    test('no file pins the simulator to one literal architecture', () {
      for (final e in files.entries) {
        final text = stripLineComments(e.value);
        expect(literal.hasMatch(text), isFalse,
            reason: '${e.key} pins ARCHS for the simulator to one literal');
        expect(excludesX86.hasMatch(text), isFalse,
            reason: '${e.key} excludes x86_64 from the simulator');
        expect(text, isNot(contains('arm64 x86_64')),
            reason: '${e.key} asks for two simulator slices (Xcode 27 lipo)');
      }
    });

    test(
        'the lookup table covers arm64, arm64e (Flutter runs arch -arm64e) and '
        'x86_64, in the app xcconfig and in the Podfile', () {
      for (final name in [
        'ios/Flutter/WattByte.xcconfig',
        'ios/Podfile',
      ]) {
        final text = stripLineComments(files[name]!);
        expect(text, contains('WB_SIM_ARCH_FOR_arm64'), reason: name);
        expect(text, contains('WB_SIM_ARCH_FOR_arm64e'), reason: name);
        expect(text, contains('WB_SIM_ARCH_FOR_x86_64'), reason: name);
        expect(
            text,
            contains(
                r'$(WB_SIM_ARCH_FOR_$(NATIVE_ARCH_ACTUAL):default=$(ARCHS_STANDARD))'),
            reason: '$name: a host the table does not know falls back to '
                'Xcode\'s default');
      }
      final x = stripLineComments(files['ios/Flutter/WattByte.xcconfig']!);
      expect(
          RegExp(r'WB_SIM_ARCH_FOR_arm64\s*=\s*arm64\s*$', multiLine: true)
              .hasMatch(x),
          isTrue);
      expect(
          RegExp(r'WB_SIM_ARCH_FOR_arm64e\s*=\s*arm64\s*$', multiLine: true)
              .hasMatch(x),
          isTrue,
          reason: 'arm64e is a device architecture; the simulator needs arm64');
      expect(
          RegExp(r'WB_SIM_ARCH_FOR_x86_64\s*=\s*x86_64\s*$', multiLine: true)
              .hasMatch(x),
          isTrue);
    });

    test('the rule applies to the simulator SDK only, not to devices', () {
      final x = stripLineComments(files['ios/Flutter/WattByte.xcconfig']!);
      final archsLines =
          x.split('\n').where((l) => RegExp(r'^\s*ARCHS').hasMatch(l)).toList();
      expect(archsLines, isNotEmpty);
      for (final l in archsLines) {
        expect(l, startsWith('ARCHS[sdk=iphonesimulator*]'),
            reason: 'an unconditional ARCHS would also change device builds');
      }
      expect(x, isNot(matches(RegExp(r'^\s*EXCLUDED_ARCHS', multiLine: true))),
          reason: "EXCLUDED_ARCHS stays with Flutter's Generated.xcconfig");
    });

    test('Debug and Release xcconfigs both include the WattByte settings', () {
      for (final name in ['Debug', 'Release']) {
        final text = files['ios/Flutter/$name.xcconfig']!;
        expect(text, contains('#include "Generated.xcconfig"'));
        expect(text, contains('#include "WattByte.xcconfig"'));
        // Local.xcconfig stays last so a developer can override.
        expect(text.lastIndexOf('Local.xcconfig'),
            greaterThan(text.indexOf('WattByte.xcconfig')));
      }
    });
  });

  group('iOS: iPhone only, portrait only (docs/PLATFORM_SUPPORT.md)', () {
    final info = parsePlistDict(read('ios/Runner/Info.plist'));

    test('every target builds for the iPhone family only', () {
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      final values = RegExp(r'TARGETED_DEVICE_FAMILY\s*=\s*"?([^;"]+)"?\s*;')
          .allMatches(project)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(values.length, greaterThanOrEqualTo(6),
          reason: 'Runner and the widget, Debug/Release/Profile each');
      expect(values.toSet(), {'1'},
          reason: 'family 2 (iPad) is deliberately not supported in v1');
    });

    test(
        'Info.plist: portrait is the only orientation, on iPhone and iPad keys',
        () {
      expect(info['UISupportedInterfaceOrientations'],
          ['UIInterfaceOrientationPortrait']);
      expect(
          info.containsKey('UISupportedInterfaceOrientations~ipad'), isFalse);
      expect(read('ios/Runner/Info.plist'), isNot(contains('Landscape')));
      expect(
          read('ios/Runner/Info.plist'), isNot(contains('PortraitUpsideDown')));
    });

    test('UIBackgroundModes is limited to fetch', () {
      expect(info['UIBackgroundModes'], ['fetch']);
    });

    test('every deployment target is iOS 15.0', () {
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([\d.]+)\s*;')
          .allMatches(project)
          .map((m) => m.group(1))
          .toSet();
      expect(targets, {'15.0'});
      expect(read('ios/Podfile'), contains("platform :ios, '15.0'"));
    });
  });

  group('iOS: App Transport Security and the local network', () {
    for (final plist in [
      'ios/Runner/Info.plist',
      'ios/WattByteWidget/Info.plist',
    ]) {
      test('$plist carries no ATS exception and no local-network keys', () {
        final text = read(plist);
        final dict = parsePlistDict(text);
        for (final key in [
          'NSAppTransportSecurity',
          'NSLocalNetworkUsageDescription',
          'NSBonjourServices',
        ]) {
          expect(dict.containsKey(key), isFalse, reason: '$plist has $key');
        }
        // Not even as text (a commented-out exception included).
        expect(
            stripXmlComments(text), isNot(contains('NSAllowsArbitraryLoads')));
        expect(
            stripXmlComments(text), isNot(contains('NSAllowsLocalNetworking')));
      });
    }

    test(
        'the development-only injection is a build phase that leaves Release '
        'alone', () {
      final project = read('ios/Runner.xcodeproj/project.pbxproj');
      final phase = RegExp(
              r'name = "WattByte Debug Local Network";[\s\S]*?shellScript = "((?:[^"\\]|\\.)*)";')
          .firstMatch(project);
      expect(phase, isNotNull, reason: 'the build phase exists');
      final script = phase!.group(1)!.replaceAll(r'\n', '\n');
      expect(script, contains('NSAppTransportSecurity'));
      expect(script, contains('NSAllowsLocalNetworking'));
      expect(script, isNot(contains('NSAllowsArbitraryLoads')),
          reason: 'only local networking, never "allow everything"');
      // The guard: only *debug* and *profile* configurations get the keys, and
      // every other configuration exits before the first plutil call.
      expect(script, contains('*debug*|*profile*) ;;'));
      final guard = script.indexOf('exit 0');
      final firstWrite = script.indexOf('plutil -replace');
      expect(guard, greaterThan(-1));
      expect(firstWrite, greaterThan(guard),
          reason: 'the early exit for Release comes before any write');
      // It edits the BUILT plist, never the tracked one.
      expect(script, contains(r'${TARGET_BUILD_DIR}/${INFOPLIST_PATH}'));
      expect(script, isNot(contains('ios/Runner/Info.plist')));
    });
  });

  group('iOS: privacy manifests', () {
    final manifests = <String, String>{
      'Runner': 'ios/Runner/PrivacyInfo.xcprivacy',
      'WattByteWidget': 'ios/WattByteWidget/PrivacyInfo.xcprivacy',
      'wattbyte_system':
          'packages/wattbyte_system/ios/Resources/PrivacyInfo.xcprivacy',
    };

    for (final e in manifests.entries) {
      group(e.key, () {
        late Map<String, Object?> m;
        setUpAll(() => m = parsePlistDict(read(e.value)));

        test('is a well-formed property list that declares no tracking', () {
          expect(m['NSPrivacyTracking'], false);
          expect(m['NSPrivacyTrackingDomains'], isEmpty);
          expect(m['NSPrivacyCollectedDataTypes'], isA<List>());
          expect(m['NSPrivacyAccessedAPITypes'], isA<List>());
        });

        test(
            'every collected data type is linked, not tracking, with a purpose',
            () {
          final collected = (m['NSPrivacyCollectedDataTypes'] as List)
              .cast<Map<String, Object?>>();
          final seen = <String>{};
          for (final c in collected) {
            final type = c['NSPrivacyCollectedDataType'] as String;
            expect(type, startsWith('NSPrivacyCollectedDataType'));
            expect(seen.add(type), isTrue, reason: 'duplicate $type');
            expect(c['NSPrivacyCollectedDataTypeTracking'], false,
                reason: type);
            expect(c['NSPrivacyCollectedDataTypeLinked'], isA<bool>(),
                reason: type);
            expect(c['NSPrivacyCollectedDataTypePurposes'], isNotEmpty,
                reason: type);
            for (final purpose
                in c['NSPrivacyCollectedDataTypePurposes'] as List) {
              expect(purpose, startsWith('NSPrivacyCollectedDataTypePurpose'));
              expect(
                  purpose,
                  isNot(
                      'NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising'));
              expect(
                  purpose,
                  isNot(
                      'NSPrivacyCollectedDataTypePurposeDeveloperAdvertising'));
              expect(
                  purpose, isNot('NSPrivacyCollectedDataTypePurposeAnalytics'));
            }
          }
        });

        test('every required-reason API has a category and reason codes', () {
          final apis = (m['NSPrivacyAccessedAPITypes'] as List)
              .cast<Map<String, Object?>>();
          final seen = <String>{};
          for (final a in apis) {
            final category = a['NSPrivacyAccessedAPIType'] as String;
            expect(category, startsWith('NSPrivacyAccessedAPICategory'));
            expect(seen.add(category), isTrue, reason: 'duplicate $category');
            final reasons = a['NSPrivacyAccessedAPITypeReasons'] as List;
            expect(reasons, isNotEmpty, reason: category);
            for (final r in reasons) {
              expect(r, matches(RegExp(r'^[A-Z0-9]{4}\.[0-9]$')),
                  reason: '$category: "$r" is not an Apple reason code');
            }
          }
        });
      });
    }

    test('the widget collects nothing', () {
      final m = parsePlistDict(read(manifests['WattByteWidget']!));
      expect(m['NSPrivacyCollectedDataTypes'], isEmpty);
    });

    test('the plugin manifest is shipped with the pod', () {
      final podspec =
          read('packages/wattbyte_system/ios/wattbyte_system.podspec');
      expect(podspec, contains('Resources/PrivacyInfo.xcprivacy'));
      expect(podspec, contains('resource_bundles'));
    });

    test('the manifests agree on the boot-time API the plugin uses', () {
      List<String> categories(String path) =>
          (parsePlistDict(read(path))['NSPrivacyAccessedAPITypes'] as List)
              .cast<Map<String, Object?>>()
              .map((a) => a['NSPrivacyAccessedAPIType'] as String)
              .toList();
      expect(categories(manifests['Runner']!),
          contains('NSPrivacyAccessedAPICategorySystemBootTime'));
      expect(categories(manifests['wattbyte_system']!),
          contains('NSPrivacyAccessedAPICategorySystemBootTime'));
      expect(
          read(
              'packages/wattbyte_system/ios/Classes/WattByteSystemPlugin.swift'),
          contains('kern.boottime'));
    });

    test('plist parser sanity: it rejects malformed files', () {
      const header = '<?xml version="1.0"?><plist version="1.0">';
      expect(() => parsePlist('$header<dict><key>a</key></dict></plist>'),
          throwsFormatException);
      expect(() => parsePlist('$header<dict><key>a</key><true/></plist>'),
          throwsFormatException);
      expect(
          () => parsePlist(
              '$header<dict><key>a</key><true/><key>a</key><false/></dict></plist>'),
          throwsFormatException);
      expect(() => parsePlist('$header<dict></dict></plist> junk'),
          throwsFormatException);
      expect(parsePlist('$header<dict><key>a</key><array/></dict></plist>'),
          {'a': <Object?>[]});
    });
  });

  group('Android manifest', () {
    final main =
        stripXmlComments(read('android/app/src/main/AndroidManifest.xml'));
    final debug =
        stripXmlComments(read('android/app/src/debug/AndroidManifest.xml'));
    final profile =
        stripXmlComments(read('android/app/src/profile/AndroidManifest.xml'));

    String? attribute(String manifest, String element, String name) {
      final tag = RegExp('<$element\\b([^>]*)>').firstMatch(manifest);
      if (tag == null) return null;
      return RegExp('$name\\s*=\\s*"([^"]*)"')
          .firstMatch(tag.group(1)!)
          ?.group(1);
    }

    test('INTERNET is requested (the cloud account, sync and AI need it)', () {
      expect(
          main,
          contains(
              '<uses-permission android:name="android.permission.INTERNET"'));
    });

    test('backups are off: not the cloud, not a device transfer', () {
      expect(attribute(main, 'application', 'android:allowBackup'), 'false');
      expect(
          attribute(main, 'application', 'android:fullBackupContent'), 'false');
      expect(attribute(main, 'application', 'android:dataExtractionRules'),
          '@xml/data_extraction_rules');
      final rules = stripXmlComments(
          read('android/app/src/main/res/xml/data_extraction_rules.xml'));
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp('<$section>([\\s\\S]*?)</$section>')
            .firstMatch(rules)
            ?.group(1);
        expect(body, isNotNull, reason: section);
        for (final domain in [
          'root',
          'file',
          'database',
          'sharedpref',
          'external'
        ]) {
          expect(body, contains('<exclude domain="$domain" />'),
              reason: '$section excludes $domain');
        }
        expect(body, isNot(contains('<include')), reason: section);
      }
    });

    test('cleartext HTTP is off in main and on only in the debug manifest', () {
      expect(attribute(main, 'application', 'android:usesCleartextTraffic'),
          'false');
      expect(attribute(debug, 'application', 'android:usesCleartextTraffic'),
          'true');
      expect(attribute(debug, 'application', 'tools:replace'),
          'android:usesCleartextTraffic');
      expect(attribute(profile, 'application', 'android:usesCleartextTraffic'),
          isNull,
          reason: 'a profile (near-release) build inherits "false"');
      expect(Directory('android/app/src/release').existsSync(), isFalse,
          reason: 'a release source set could silently re-enable cleartext');
      expect(main, isNot(contains('networkSecurityConfig')));
      expect(main, isNot(contains('android:debuggable')));
    });

    test('MainActivity is portrait only', () {
      final activity =
          RegExp(r'<activity\b([^>]*)>').firstMatch(main)!.group(1)!;
      expect(activity, contains('android:name=".MainActivity"'));
      expect(activity, contains('android:screenOrientation="portrait"'));
      expect(activity, isNot(contains('landscape')));
      expect(activity, isNot(contains('sensor')));
      expect(activity, isNot(contains('fullSensor')));
      expect(activity, isNot(contains('unspecified')));
    });

    test('release signing material comes from outside the repository', () {
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, contains('key.properties'));
      expect(gradle, contains('WATTBYTE_KEYSTORE_FILE'));
      for (final field in ['storePassword', 'keyPassword']) {
        // Assignments take their value from `signingValue(...)`, never a literal.
        for (final m in RegExp('$field\\s*=\\s*(.+)').allMatches(gradle)) {
          expect(m.group(1), startsWith('signingValue('),
              reason: '$field must not be a literal');
        }
      }
      final releaseBlock = RegExp(r'release\s*\{([\s\S]*?)\n        \}')
          .firstMatch(gradle.substring(gradle.indexOf('buildTypes')))
          ?.group(1);
      expect(releaseBlock, isNotNull);
      expect(releaseBlock, isNot(contains('getByName("debug")')),
          reason: 'release is never signed with the debug key');
      expect(releaseBlock, contains('isMinifyEnabled = true'));
    });
  });

  group('no signing material in the tree', () {
    // The .gitignore rules keep these out of a commit; this checks the working
    // tree itself (nothing to ignore, nothing to forget).
    const forbiddenNames = {
      'key.properties',
      'local.keystore',
      'upload-keystore.jks',
      'google-services.json',
      'GoogleService-Info.plist',
      'Local.xcconfig',
    };
    const forbiddenExtensions = {
      '.jks',
      '.keystore',
      '.p12',
      '.p8',
      '.pfx',
      '.pem',
      '.cer',
      '.mobileprovision',
      '.provisionprofile',
      '.certSigningRequest',
    };
    const skipped = {
      'build',
      '.dart_tool',
      '.symlinks',
      'Pods',
      'DerivedData',
      '.gradle',
      '.git',
      'node_modules',
      'ephemeral',
    };

    List<String> offenders(Directory root) {
      final found = <String>[];
      void walk(Directory d) {
        for (final e in d.listSync(followLinks: false)) {
          final name = p.basename(e.path);
          if (e is Directory) {
            if (!skipped.contains(name)) walk(e);
          } else if (e is File) {
            if (forbiddenNames.contains(name) ||
                forbiddenExtensions.contains(p.extension(name))) {
              found.add(e.path);
            }
          }
        }
      }

      if (root.existsSync()) walk(root);
      return found;
    }

    test(
        'apps/mobile has no keystore, certificate, key.properties or '
        'Local.xcconfig', () {
      expect(offenders(Directory('.')), isEmpty);
    });

    test('the rest of the repository (outside node_modules) has none either',
        () {
      for (final dir in [
        '../../docs',
        '../../scripts',
        '../../infrastructure',
        '../../packages',
        '../api'
      ]) {
        expect(offenders(Directory(dir)), isEmpty, reason: dir);
      }
    });

    test('only the template files exist', () {
      expect(File('android/key.properties.example').existsSync(), isTrue);
      expect(File('ios/Flutter/Local.xcconfig.example').existsSync(), isTrue);
      final example = read('android/key.properties.example');
      expect(example, contains('CHANGE_ME'));
      expect(
          example,
          isNot(matches(RegExp(r'password\s*=\s*(?!CHANGE_ME)\S+',
              caseSensitive: false))),
          reason: 'the template carries placeholders only');
    });

    test('the ignore rules cover signing material', () {
      final rootIgnore = read('../../.gitignore');
      for (final rule in [
        'key.properties',
        '*.jks',
        '*.keystore',
        '*.p12',
        '*.mobileprovision',
        'apps/mobile/ios/Flutter/Local.xcconfig',
        '.env',
      ]) {
        expect(rootIgnore, contains(rule), reason: rule);
      }
      expect(read('android/.gitignore'), contains('key.properties'));
    });
  });
}
