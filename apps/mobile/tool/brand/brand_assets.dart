// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Renders WattByte's launcher icons, launch logo and Android vector layers from the SAME gradient and bolt
// geometry the app draws in `WattByteMark` (lib/ui/widgets/wb_widgets.dart) with the colours of `WbColors`
// (lib/ui/theme.dart). Nothing here is a new logo: the numbers below are copied from those two files and
// `generate_brand_assets_test.dart` fails when they drift apart.
//
// Entry point: tool/generate_brand_assets.sh (writes) and tool/generate_brand_assets.sh --check (verifies).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

// ---- The mark, copied from lib/ui/theme.dart and lib/ui/widgets/wb_widgets.dart ------------------------
const kGradientStart = Color(0xFF67D2FF); // WbColors.byteGradient, top left
const kGradientEnd = Color(0xFF2A9DF4); //   WbColors.byteGradient, bottom right
const kBoltColor = Color(0xFFFFC53D); //     WbColors.bolt
const kShadowColor = Color(
    0xFF38BDF8); //   WbColors.byte (the mark's shadow is byte at 35 % alpha)
const kCornerRadiusRatio = 0.3; //           BorderRadius.circular(size * 0.3)
const kShadowBlurRatio = 0.4; //             blurRadius: size * 0.4
const kShadowOffsetRatio = 0.15; //          offset: Offset(0, size * 0.15)
const kShadowAlpha = 0.35;
const kLightBackground =
    Color(0xFFF4F5F8); // WbColors.lightBg  -> launch screen, light
const kDarkBackground =
    Color(0xFF0A0B0F); //  WbColors.darkBg   -> launch screen, dark

/// `_BoltPainter`: fractions of the mark's width / height.
const List<Offset> kBolt = <Offset>[
  Offset(0.56, 0.12),
  Offset(0.28, 0.56),
  Offset(0.47, 0.56),
  Offset(0.42, 0.88),
  Offset(0.72, 0.44),
  Offset(0.53, 0.44),
];

const kMarkGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[kGradientStart, kGradientEnd],
);

// ---- Platform geometry -------------------------------------------------------------------------------
/// Android adaptive icons are drawn on a 108 dp canvas of which only the centre 72 dp are guaranteed to be
/// visible whatever mask the launcher applies. The mark is laid out inside that visible window, so the
/// bolt keeps the in-app proportions and stays inside the 66 dp safe zone (its farthest point is at
/// 0.39 * 72 dp = 28 dp from the centre).
const kAdaptiveCanvasDp = 108.0;
const kAdaptiveVisibleDp = 72.0;

/// The launch logo is the in-app `WattByteMark(size: 96)` that the splash screen in lib/app.dart shows, drawn
/// with its shadow on a larger transparent canvas so the blur is never clipped.
const kLaunchMarkPt = 96.0;
const kLaunchCanvasPt = 240.0;

// ---- Painting ---------------------------------------------------------------------------------------
Path boltPath(Rect r) {
  final path = Path()
    ..moveTo(r.left + r.width * kBolt[0].dx, r.top + r.height * kBolt[0].dy);
  for (final p in kBolt.skip(1)) {
    path.lineTo(r.left + r.width * p.dx, r.top + r.height * p.dy);
  }
  return path..close();
}

void paintBolt(Canvas canvas, Rect r, {Color color = kBoltColor}) {
  canvas.drawPath(boltPath(r), Paint()..color = color);
}

/// The gradient square of the mark. [radiusRatio] 0 is the full-bleed square iOS wants (the OS applies its own
/// mask); [circle] is the legacy round launcher icon.
void paintMarkBody(Canvas canvas, Rect r,
    {double radiusRatio = 0, bool circle = false}) {
  final paint = Paint()..shader = kMarkGradient.createShader(r);
  if (circle) {
    canvas.drawOval(r, paint);
  } else if (radiusRatio == 0) {
    canvas.drawRect(r, paint);
  } else {
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(r.width * radiusRatio)),
        paint);
  }
}

/// The in-app mark including its drop shadow (identical to `WattByteMark`'s BoxDecoration).
void paintMarkWithShadow(Canvas canvas, Rect r) {
  final shadow = BoxShadow(
    color: kShadowColor.withValues(alpha: kShadowAlpha),
    blurRadius: r.width * kShadowBlurRatio,
    offset: Offset(0, r.width * kShadowOffsetRatio),
  );
  final rrect =
      RRect.fromRectAndRadius(r, Radius.circular(r.width * kCornerRadiusRatio));
  canvas.drawRRect(rrect.shift(shadow.offset), shadow.toPaint());
  paintMarkBody(canvas, r, radiusRatio: kCornerRadiusRatio);
  paintBolt(canvas, r);
}

/// The 72 dp window inside the 108 dp adaptive canvas, in canvas units of [size].
Rect adaptiveWindow(double size) {
  final side = size * kAdaptiveVisibleDp / kAdaptiveCanvasDp;
  return Rect.fromCenter(
      center: Offset(size / 2, size / 2), width: side, height: side);
}

// ---- Rasterising and PNG encoding -------------------------------------------------------------------
class Raster {
  Raster(this.width, this.height, this.rgba);
  final int width;
  final int height;

  /// Straight (non-premultiplied) RGBA, row major.
  final Uint8List rgba;
}

Future<Raster> render(
    int width, int height, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
      recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  image.dispose();
  picture.dispose();
  return Raster(width, height,
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
}

/// Square [size] x [size] raster; [paint] works in pixels of that size.
Future<Raster> renderSquare(
        int size, void Function(Canvas canvas, double size) paint) =>
    render(size, size, (c) => paint(c, size.toDouble()));

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

Uint8List _chunk(String type, List<int> data) {
  final body = <int>[...type.codeUnits, ...data];
  final out = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(body)
    ..add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
  return out.toBytes();
}

/// 8-bit PNG tagged sRGB. With [alpha] false the file is RGB (colour type 2) with NO alpha channel, which is what
/// the App Store requires of the 1024 pt marketing icon; every pixel must then be opaque.
Uint8List encodePng(Raster r, {required bool alpha}) {
  final bpp = alpha ? 4 : 3;
  final stride = r.width * bpp;
  final filtered = BytesBuilder();
  Uint8List? previous;
  for (var y = 0; y < r.height; y++) {
    final row = Uint8List(stride);
    for (var x = 0; x < r.width; x++) {
      final src = (y * r.width + x) * 4;
      if (!alpha && r.rgba[src + 3] != 255) {
        throw StateError(
            'pixel ($x,$y) is not opaque; cannot drop the alpha channel');
      }
      row.setRange(x * bpp, x * bpp + bpp, r.rgba.sublist(src, src + bpp));
    }
    // Filter type 2 ("Up"): smooth gradients compress far better than unfiltered rows.
    final line = Uint8List(stride + 1)..[0] = 2;
    for (var i = 0; i < stride; i++) {
      line[i + 1] = (row[i] - (previous == null ? 0 : previous[i])) & 0xFF;
    }
    filtered.add(line);
    previous = row;
  }
  final header = ByteData(13)
    ..setUint32(0, r.width)
    ..setUint32(4, r.height)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2);
  final png = BytesBuilder()
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('sRGB', const <int>[0]))
    ..add(_chunk('IDAT', ZLibEncoder(level: 9).convert(filtered.toBytes())))
    ..add(_chunk('IEND', const <int>[]));
  return png.toBytes();
}

/// Decodes a PNG written by any encoder to straight RGBA (for the drift check).
Future<Raster> decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final data =
      await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final raster = Raster(frame.image.width, frame.image.height,
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  frame.image.dispose();
  codec.dispose();
  return raster;
}

// ---- Android vector drawables -----------------------------------------------------------------------
String _n(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String _argb(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _boltPathData(Rect r) {
  final pts = kBolt
      .map((p) =>
          '${_n(r.left + r.width * p.dx)},${_n(r.top + r.height * p.dy)}')
      .toList();
  return 'M${pts.first} ${pts.skip(1).map((p) => 'L$p').join(' ')} Z';
}

const _generated =
    '<!-- Generated by tool/generate_brand_assets.sh from the in-app WattByteMark; do not edit by hand. -->';

String _vector(double dp, String body, {bool aapt = false}) =>
    '''<?xml version="1.0" encoding="utf-8"?>
$_generated
<vector xmlns:android="http://schemas.android.com/apk/res/android"${aapt ? '\n    xmlns:aapt="http://schemas.android.com/aapt"' : ''}
    android:width="${_n(dp)}dp"
    android:height="${_n(dp)}dp"
    android:viewportWidth="${_n(dp)}"
    android:viewportHeight="${_n(dp)}">
$body</vector>
''';

String _gradientFill(Rect r) => '''        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="${_n(r.left)}"
                android:startY="${_n(r.top)}"
                android:endX="${_n(r.right)}"
                android:endY="${_n(r.bottom)}">
                <item android:offset="0" android:color="${_argb(kGradientStart)}" />
                <item android:offset="1" android:color="${_argb(kGradientEnd)}" />
            </gradient>
        </aapt:attr>
''';

String _roundedRectPath(Rect r, double radius) {
  String p(double x, double y) => '${_n(x)},${_n(y)}';
  final rad = _n(radius);
  return 'M${p(r.left + radius, r.top)} H${_n(r.right - radius)} A$rad,$rad 0 0 1 ${p(r.right, r.top + radius)} '
      'V${_n(r.bottom - radius)} A$rad,$rad 0 0 1 ${p(r.right - radius, r.bottom)} '
      'H${_n(r.left + radius)} A$rad,$rad 0 0 1 ${p(r.left, r.bottom - radius)} '
      'V${_n(r.top + radius)} A$rad,$rad 0 0 1 ${p(r.left + radius, r.top)} Z';
}

/// Adaptive-icon foreground: only the bolt, in the 72 dp window of the 108 dp canvas.
String androidForegroundXml() => _vector(
      kAdaptiveCanvasDp,
      '    <path\n        android:fillColor="${_argb(kBoltColor)}"\n'
      '        android:pathData="${_boltPathData(adaptiveWindow(kAdaptiveCanvasDp))}" />\n',
    );

/// Themed-icon (Android 13+) layer: the same bolt, one opaque colour; the system recolours it.
String androidMonochromeXml() => _vector(
      kAdaptiveCanvasDp,
      '    <path\n        android:fillColor="#FF000000"\n'
      '        android:pathData="${_boltPathData(adaptiveWindow(kAdaptiveCanvasDp))}" />\n',
    );

/// Adaptive-icon background: the mark's gradient, laid out so the visible 72 dp window shows it corner to corner.
String androidBackgroundXml() => _vector(
      kAdaptiveCanvasDp,
      '    <path android:pathData="M0,0h${_n(kAdaptiveCanvasDp)}v${_n(kAdaptiveCanvasDp)}h-${_n(kAdaptiveCanvasDp)}z">\n'
      '${_gradientFill(adaptiveWindow(kAdaptiveCanvasDp))}    </path>\n',
      aapt: true,
    );

/// The full mark (rounded square + bolt, no shadow) as a [dp] x [dp] vector with the square [markDp] wide and
/// centred: the Android 12+ splash icon (288 dp canvas, 132 dp mark inside its 192 dp circle) and the
/// pre-Android-12 launch background (96 dp, like the in-app splash).
String androidMarkXml({required double canvasDp, required double markDp}) {
  final offset = (canvasDp - markDp) / 2;
  final r = Rect.fromLTWH(offset, offset, markDp, markDp);
  return _vector(
    canvasDp,
    '    <path android:pathData="${_roundedRectPath(r, markDp * kCornerRadiusRatio)}">\n'
    '${_gradientFill(r)}    </path>\n'
    '    <path\n        android:fillColor="${_argb(kBoltColor)}"\n'
    '        android:pathData="${_boltPathData(r)}" />\n',
    aapt: true,
  );
}

// ---- Catalog JSON ------------------------------------------------------------------------------------
/// iPhone launcher sizes (points, scale). iPad idioms are deliberately absent: v1 is iPhone only.
const List<(int pt, int scale)> kIphoneIcons = <(int, int)>[
  (20, 2),
  (20, 3),
  (29, 2),
  (29, 3),
  (40, 2),
  (40, 3),
  (60, 2),
  (60, 3),
];

String iosIconFile(int pt, int scale) => 'Icon-App-${pt}x$pt@${scale}x.png';

String appIconContentsJson() {
  final images = <String>[
    for (final (pt, scale) in kIphoneIcons)
      '    {\n      "size" : "${pt}x$pt",\n      "idiom" : "iphone",\n      "filename" : "${iosIconFile(pt, scale)}",\n'
          '      "scale" : "${scale}x"\n    }',
    '    {\n      "size" : "1024x1024",\n      "idiom" : "ios-marketing",\n      "filename" : "Icon-App-1024x1024@1x.png",\n'
        '      "scale" : "1x"\n    }',
  ];
  return '{\n  "images" : [\n${images.join(',\n')}\n  ],\n  "info" : {\n    "version" : 1,\n    "author" : "xcode"\n  }\n}\n';
}

String launchLogoContentsJson() => '''{
  "images" : [
    {
      "idiom" : "universal",
      "filename" : "LaunchLogo.png",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "filename" : "LaunchLogo@2x.png",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "filename" : "LaunchLogo@3x.png",
      "scale" : "3x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
''';

String _component(double v) => v.toStringAsFixed(9);

String _colorEntry(Color c, {bool dark = false}) => '''    {
${dark ? '''      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
''' : ''}      "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "red" : "${_component(c.r)}",
          "green" : "${_component(c.g)}",
          "blue" : "${_component(c.b)}",
          "alpha" : "1.000"
        }
      }
    }''';

/// `LaunchBackground` named colour: the theme's light and dark page background.
String launchBackgroundContentsJson() => '''{
  "colors" : [
${_colorEntry(kLightBackground)},
${_colorEntry(kDarkBackground, dark: true)}
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
''';
