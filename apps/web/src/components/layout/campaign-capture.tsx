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
