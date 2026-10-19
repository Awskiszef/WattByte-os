import { ImageResponse } from 'next/og';

export const size = { width: 180, height: 180 };
export const contentType = 'image/png';

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#0a0a0a',
          borderRadius: 40,
        }}
      >
        <svg viewBox="0 0 32 32" width="120" height="120">
          <path d="M18.5 6.5 10 18h5.2l-1.7 7.5L22 13h-5.3z" fill="#f0b35b" />
        </svg>
      </div>
    ),
    size,
  );
}
