// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import nextVitals from 'eslint-config-next/core-web-vitals';
import base from '../../eslint.config.js';

export default [
  { ignores: ['.next/**', 'out/**', 'next-env.d.ts'] },
  ...nextVitals,
  ...base,
];
