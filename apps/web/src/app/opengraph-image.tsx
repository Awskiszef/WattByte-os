// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { ImageResponse } from 'next/og';
import { site } from '@/config/site';

export const alt = `${site.name}: ${site.tagline}`;
export const size = { width: 1200, height: 630 };
export const contentType = 'image/png';

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'space-between',
          padding: 72,
          background: 'linear-gradient(135deg, #000 0%, #0b0b0d 100%)',
          color: '#f4f4f5',
          fontFamily: 'sans-serif',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
          <svg viewBox="0 0 32 32" width="56" height="56">
            <rect x="2" y="2" width="28" height="28" rx="8" fill="#f4f4f5" />
            <path d="M18.5 6.5 10 18h5.2l-1.7 7.5L22 13h-5.3z" fill="#000" />
          </svg>
          <div style={{ fontSize: 40, fontWeight: 600, letterSpacing: -1 }}>{site.name}</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <div style={{ fontSize: 76, fontWeight: 600, letterSpacing: -3, lineHeight: 1.02, maxWidth: 900 }}>
            Know what your device consumes.
          </div>
          <div style={{ fontSize: 30, color: '#a1a1aa', maxWidth: 900 }}>
            Battery, data and energy usage turned into clear insights, costs and recommendations.
          </div>
        </div>
        <div style={{ display: 'flex', gap: 40, fontSize: 26, color: '#a1a1aa' }}>
          <span style={{ color: '#f0b35b' }}>6.3 Wh today</span>
          <span style={{ color: '#62d0e6' }}>1.8 GB mobile</span>
          <span>wattbyte.app</span>
        </div>
      </div>
    ),
    size,
  );
}
