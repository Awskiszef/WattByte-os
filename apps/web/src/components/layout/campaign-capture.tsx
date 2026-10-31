// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

'use client';

import { useEffect } from 'react';
import { rememberCampaign } from '@/lib/campaign';

/** Reads the `utm_*` tags of the page the visitor landed on; see `src/lib/campaign.ts`. */
export function CampaignCapture() {
  useEffect(() => {
    rememberCampaign(window.location.search);
  }, []);
  return null;
}
