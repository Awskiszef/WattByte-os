// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Generates (WB_BRAND_MODE=write) or verifies (default / WB_BRAND_MODE=check) every launcher-icon and
// launch-screen asset of the app. Run it through tool/generate_brand_assets.sh from apps/mobile.
//
// It lives under tool/ (not test/) on purpose: the regular `flutter test` run does not render images.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brand_assets.dart';

final bool _write = Platform.environment['WB_BRAND_MODE'] == 'write';

const _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _iosLogo = 'ios/Runner/Assets.xcassets/LaunchLogo.imageset';
const _iosColor = 'ios/Runner/Assets.xcassets/LaunchBackground.colorset';
const _androidRes = 'android/app/src/main/res';
const _branding = 'assets/branding';

class _Artifact {
  _Artifact.png(this.path, this.raster, {required this.alpha}) : text = null;
  _Artifact.text(this.path, this.text)
      : raster = null,
        alpha = true;

  final String path;
  final Future<Raster>? raster;
  final bool alpha;
  final String? text;
}

Future<List<_Artifact>> _artifacts() async {
  Future<Raster> sq(int size, void Function(Canvas, double) paint) =>
      renderSquare(size, paint);

  final list = <_Artifact>[
    // ---- Sources kept in assets/branding (store listings, other tooling) ----
    _Artifact.png(
      '$_branding/icon.png',
      sq(1024, _fullBleedIcon),
      alpha: false,
    ),
    _Artifact.png(
      '$_branding/icon_foreground.png',
      sq(1024, (c, s) => paintBolt(c, adaptiveWindow(s))),
      alpha: true,
    ),
    _Artifact.png(
      '$_branding/icon_background.png',
      sq(1024, (c, s) {
        // The gradient spans the visible 72 dp window; outside it the colours clamp, like the Android vector.
        c.drawRect(Rect.fromLTWH(0, 0, s, s),
            Paint()..shader = kMarkGradient.createShader(adaptiveWindow(s)));
      }),
      alpha: false,
    ),
    _Artifact.png(
      '$_branding/icon_monochrome.png',
      sq(
          1024,
          (c, s) =>
              paintBolt(c, adaptiveWindow(s), color: const Color(0xFF000000))),
      alpha: true,
    ),
    _Artifact.png('$_branding/launch_logo.png', sq(720, _launchLogo(3)),
        alpha: true),

    // ---- iOS: iPhone launcher icons, full-bleed and opaque (the OS applies the mask) ----
    for (final (pt, scale) in kIphoneIcons)
      _Artifact.png('$_iosIcons/${iosIconFile(pt, scale)}',
          sq(pt * scale, _fullBleedIcon),
          alpha: false),
    _Artifact.png(
        '$_iosIcons/Icon-App-1024x1024@1x.png', sq(1024, _fullBleedIcon),
        alpha: false),
    _Artifact.text('$_iosIcons/Contents.json', appIconContentsJson()),

    // ---- iOS launch screen ----
    for (final scale in const [1, 2, 3])
      _Artifact.png(
        '$_iosLogo/LaunchLogo${scale == 1 ? '' : '@${scale}x'}.png',
        sq((kLaunchCanvasPt * scale).round(), _launchLogo(scale)),
        alpha: true,
      ),
    _Artifact.text('$_iosLogo/Contents.json', launchLogoContentsJson()),
    _Artifact.text('$_iosColor/Contents.json', launchBackgroundContentsJson()),

    // ---- Android: adaptive layers (vector), splash icon, legacy launcher bitmaps ----
    _Artifact.text('$_androidRes/drawable/ic_launcher_foreground.xml',
        androidForegroundXml()),
    _Artifact.text('$_androidRes/drawable/ic_launcher_monochrome.xml',
        androidMonochromeXml()),
    _Artifact.text('$_androidRes/drawable/ic_launcher_background.xml',
        androidBackgroundXml()),
    _Artifact.text('$_androidRes/drawable/splash_icon.xml',
        androidMarkXml(canvasDp: 288, markDp: 132)),
    _Artifact.text('$_androidRes/drawable/launch_logo.xml',
        androidMarkXml(canvasDp: 96, markDp: 96)),
    for (final (density, px) in const [
      ('mdpi', 48),
      ('hdpi', 72),
      ('xhdpi', 96),
      ('xxhdpi', 144),
      ('xxxhdpi', 192)
    ]) ...[
      _Artifact.png('$_androidRes/mipmap-$density/ic_launcher.png',
          sq(px, _legacyIcon(round: false)),
          alpha: true),
      _Artifact.png('$_androidRes/mipmap-$density/ic_launcher_round.png',
          sq(px, _legacyIcon(round: true)),
          alpha: true),
    ],
  ];
  return list;
}

void _fullBleedIcon(Canvas c, double s) {
  final r = Rect.fromLTWH(0, 0, s, s);
  paintMarkBody(c, r);
  paintBolt(c, r);
}

void Function(Canvas, double) _launchLogo(int scale) => (c, s) {
      final mark = kLaunchMarkPt * scale;
      paintMarkWithShadow(
          c,
          Rect.fromCenter(
              center: Offset(s / 2, s / 2), width: mark, height: mark));
    };

/// Legacy (pre-adaptive) launcher bitmap: the in-app mark, or the same artwork on a circle, with 2/48 padding.
void Function(Canvas, double) _legacyIcon({required bool round}) => (c, s) {
      final pad = s * 2 / 48;
      final r = Rect.fromLTWH(pad, pad, s - 2 * pad, s - 2 * pad);
      if (round) {
        paintMarkBody(c, r, circle: true);
      } else {
        paintMarkBody(c, r, radiusRatio: kCornerRadiusRatio);
      }
      paintBolt(c, r);
    };

/// Files that must not exist any more: the stock Flutter template images.
const _removed = <String>[
  '$_iosIcons/Icon-App-20x20@1x.png',
  '$_iosIcons/Icon-App-29x29@1x.png',
  '$_iosIcons/Icon-App-40x40@1x.png',
  '$_iosIcons/Icon-App-76x76@1x.png',
  '$_iosIcons/Icon-App-76x76@2x.png',
  '$_iosIcons/Icon-App-83.5x83.5@2x.png',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md',
];

bool _hasAlphaChannel(Uint8List png) {
  // IHDR colour type is byte 25: 2 = RGB, 6 = RGBA (this encoder writes nothing else).
  return png.length > 25 && (png[25] == 4 || png[25] == 6);
}

Future<double> _differingFraction(Raster a, Raster b) async {
  var bad = 0;
  for (var i = 0; i < a.rgba.length; i += 4) {
    var worst = 0;
    for (var k = 0; k < 4; k++) {
      final d = (a.rgba[i + k] - b.rgba[i + k]).abs();
      if (d > worst) worst = d;
    }
    if (worst > 16) bad++;
  }
  return bad / (a.width * a.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test turns BoxShadow blurs off to keep golden files stable; the launch logo needs the real blur.
  debugDisableShadows = false;

  test('the brand constants still match the in-app WattByteMark', () {
    final theme = File('lib/ui/theme.dart').readAsStringSync();
    final widgets = File('lib/ui/widgets/wb_widgets.dart').readAsStringSync();
    String hex(Color c) =>
        c.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');

    expect(theme, contains('Color(0x${hex(kGradientStart)})'),
        reason: 'byteGradient start');
    expect(theme, contains('Color(0x${hex(kGradientEnd)})'),
        reason: 'byteGradient end');
    expect(theme, contains('static const bolt = Color(0x${hex(kBoltColor)})'));
    expect(
        theme, contains('static const byte = Color(0x${hex(kShadowColor)})'));
    expect(theme,
        contains('static const lightBg = Color(0x${hex(kLightBackground)})'));
    expect(theme,
        contains('static const darkBg = Color(0x${hex(kDarkBackground)})'));
    expect(theme, contains('begin: Alignment.topLeft'));
    expect(theme, contains('end: Alignment.bottomRight'));

    expect(
        widgets, contains('BorderRadius.circular(size * $kCornerRadiusRatio)'));
    expect(widgets, contains('withValues(alpha: $kShadowAlpha)'));
    expect(widgets, contains('blurRadius: size * $kShadowBlurRatio'));
    expect(widgets, contains('Offset(0, size * $kShadowOffsetRatio)'));
    for (var i = 0; i < kBolt.length; i++) {
      final call = i == 0 ? 'moveTo' : 'lineTo';
      expect(widgets, contains('$call(w * ${kBolt[i].dx}, h * ${kBolt[i].dy})'),
          reason: 'bolt point $i');
    }
    expect(widgets, contains('WbColors.bolt'));
  });

  test(
      'the splash screen shows the mark at the size the launch logo is drawn for',
      () {
    final app = File('lib/app.dart').readAsStringSync();
    expect(app, contains('WattByteMark(size: ${kLaunchMarkPt.toInt()})'));
  });

  test(
      _write
          ? 'writes every brand asset'
          : 'every committed brand asset matches the renderer', () async {
    final failures = <String>[];
    for (final a in await _artifacts()) {
      final file = File(a.path);
      if (a.text != null) {
        if (_write) {
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(a.text!);
        } else if (!file.existsSync()) {
          failures.add('${a.path}: missing');
        } else if (file.readAsStringSync() != a.text) {
          failures.add('${a.path}: text differs from the generator output');
        }
        continue;
      }
      final raster = await a.raster!;
      final bytes = encodePng(raster, alpha: a.alpha);
      if (_write) {
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        continue;
      }
      if (!file.existsSync()) {
        failures.add('${a.path}: missing');
        continue;
      }
      final committed = file.readAsBytesSync();
      if (!a.alpha && _hasAlphaChannel(committed)) {
        failures.add('${a.path}: has an alpha channel');
      }
      final decoded = await decodePng(committed);
      if (decoded.width != raster.width || decoded.height != raster.height) {
        failures.add(
            '${a.path}: ${decoded.width}x${decoded.height}, expected ${raster.width}x${raster.height}');
        continue;
      }
      final differing = await _differingFraction(decoded, raster);
      if (differing > 0.001) {
        failures.add(
            '${a.path}: ${(differing * 100).toStringAsFixed(2)} % of the pixels differ from the renderer');
      }
    }
    for (final path in _removed) {
      final f = File(path);
      if (_write) {
        if (f.existsSync()) f.deleteSync();
      } else if (f.existsSync()) {
        failures.add('$path: stock Flutter template file is still present');
      }
    }
    if (_write) {
      final old = Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset');
      if (old.existsSync() && old.listSync().isEmpty) old.deleteSync();
    }
    expect(failures, isEmpty,
        reason: 'run tool/generate_brand_assets.sh to regenerate');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
