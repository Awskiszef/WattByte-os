// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The share sheet needs a non-empty anchor rectangle on iOS 26+ and on iPad;
// a missing one crashed the export ("sharePositionOrigin must be non-zero").
// These tests pin the rule: whatever the geometry, the anchor is never empty.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/ui/settings/share_anchor.dart';

void main() {
  bool usable(Rect r) =>
      r.width > 0 &&
      r.height > 0 &&
      r.left.isFinite &&
      r.top.isFinite &&
      r.width.isFinite &&
      r.height.isFinite;

  group('shareAnchorFromGeometry', () {
    test('no geometry at all falls back to a 1x1 rectangle', () {
      final r = shareAnchorFromGeometry();
      expect(r, kFallbackShareAnchor);
      expect(r, const Rect.fromLTWH(0, 0, 1, 1));
    });

    test('a missing size or a missing position falls back', () {
      expect(shareAnchorFromGeometry(topLeft: const Offset(10, 20)),
          kFallbackShareAnchor);
      expect(shareAnchorFromGeometry(size: const Size(100, 40)),
          kFallbackShareAnchor);
    });

    test('a zero-sized box falls back, even at an offset', () {
      for (final size in const [
        Size.zero,
        Size(100, 0),
        Size(0, 40),
      ]) {
        final r =
            shareAnchorFromGeometry(topLeft: const Offset(30, 60), size: size);
        expect(r, kFallbackShareAnchor, reason: '$size');
        expect(usable(r), isTrue);
      }
    });

    test('negative and non-finite geometry falls back', () {
      for (final (topLeft, size) in const [
        (Offset(0, 0), Size(-10, 40)),
        (Offset(0, 0), Size(10, -40)),
        (Offset(0, 0), Size(double.infinity, 40)),
        (Offset(0, 0), Size(double.nan, 40)),
        (Offset(double.nan, 0), Size(10, 40)),
        (Offset(0, double.infinity), Size(10, 40)),
      ]) {
        final r = shareAnchorFromGeometry(topLeft: topLeft, size: size);
        expect(r, kFallbackShareAnchor, reason: '$topLeft $size');
      }
    });

    test('a normal box is anchored to itself', () {
      final r = shareAnchorFromGeometry(
          topLeft: Offset.zero, size: const Size(360, 56));
      expect(r, const Rect.fromLTWH(0, 0, 360, 56));
    });

    test('an offset box keeps its position', () {
      final r = shareAnchorFromGeometry(
          topLeft: const Offset(20, 412.5), size: const Size(320, 56));
      expect(r, const Rect.fromLTWH(20, 412.5, 320, 56));
      expect(usable(r), isTrue);
    });
  });

  group('shareAnchorOf', () {
    test('null box', () {
      expect(shareAnchorOf(null), kFallbackShareAnchor);
    });

    test('a box that was never laid out or attached', () {
      final box = RenderConstrainedBox(
          additionalConstraints:
              const BoxConstraints.tightFor(width: 100, height: 40));
      expect(box.hasSize, isFalse);
      expect(shareAnchorOf(box), kFallbackShareAnchor);
    });

    testWidgets('an attached box: its global rectangle', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          Positioned(
              left: 50,
              top: 80,
              child: SizedBox(key: key, width: 120, height: 44)),
        ]),
      ));
      final box = key.currentContext!.findRenderObject()! as RenderBox;
      expect(shareAnchorOf(box), const Rect.fromLTWH(50, 80, 120, 44));
      expect(shareAnchorForContext(key.currentContext!),
          const Rect.fromLTWH(50, 80, 120, 44));
    });

    testWidgets('an attached zero-sized box falls back', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          Positioned(left: 50, top: 80, child: SizedBox.shrink(key: key)),
        ]),
      ));
      expect(shareAnchorForContext(key.currentContext!), kFallbackShareAnchor);
    });

    testWidgets('a context without a box (a sliver) falls back',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(key: key, child: const SizedBox(height: 10)),
        ]),
      ));
      expect(shareAnchorForContext(key.currentContext!), kFallbackShareAnchor);
    });
  });
}
