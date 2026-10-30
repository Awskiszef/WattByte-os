// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

export type FaqItem = { id: string; question: string; answer: string };

export const faq: readonly FaqItem[] = [
  {
    id: 'what-is-wattbyte',
    question: 'What is WattByte?',
    answer:
      'WattByte is a mobile app for iPhone and Android that shows how much data and energy your phone uses: mobile and Wi-Fi traffic, battery used, estimated energy in Wh and kWh, and the estimated electricity cost. It turns system counters into numbers you can read.',
  },
  {
    id: 'how-energy-is-calculated',
    question: 'How does WattByte calculate energy usage?',
    answer:
      'From the counters the operating system exposes. Where the phone reports an energy counter it is used directly; otherwise charge in mAh is multiplied by the battery voltage, and if no counter exists at all, the change in battery level is multiplied by the design capacity of your phone model. Wh becomes kWh, and the wall energy adds a charging efficiency you can adjust. Values that rely on an estimate are marked as such.',
  },
  {
    id: 'measuring-directly',
    question: 'Is WattByte measuring electricity directly?',
    answer:
      'No. Phones have no power meter an app can read. WattByte reads the battery and network counters the system provides and calculates or estimates the rest from your device parameters. It is an estimate of what the battery took in, not a reading from your wall socket.',
  },
  {
    id: 'drain',
    question: 'Does WattByte drain my battery?',
    answer:
      'It is designed not to. Counters are read when you open the app, in a short background refresh a few times an hour, and on Android once a minute only while the phone is charging. There is no always-on service.',
  },
  {
    id: 'location',
    question: 'Does WattByte track my location?',
    answer:
      'No. It never asks for location permission. The region used for currency and electricity price comes from your device region setting or system locale, and you can change it by hand.',
  },
  {
    id: 'sell-data',
    question: 'Does WattByte sell my data?',
    answer:
      'No. There is no advertising SDK, no analytics SDK and no tracker in the app. Usage data stays on your phone unless you switch on cloud sync, and even then only daily totals are uploaded.',
  },
  {
    id: 'delete-account',
    question: 'Can I delete my account?',
    answer:
      'Yes, from the Account screen in the app. Deleting the account removes it together with every synced row, device registration and AI usage record.',
  },
  {
    id: 'ios',
    question: 'Does WattByte work on iOS?',
    answer:
      'Yes, on iPhone with iOS 15 or later. iOS shares no per-app data and no battery counters with apps, so on iOS the energy figures are estimated from the battery level and the design capacity of your model, and charging is tracked while WattByte runs or refreshes in the background.',
  },
  {
    id: 'android',
    question: 'Does WattByte work on Android?',
    answer:
      'Yes, on Android 10 or later. After you grant Usage access, WattByte can show mobile and Wi-Fi totals and data by app. Where the phone reports battery charge or energy counters, they are used for more accurate figures.',
  },
  {
    id: 'cost-exact',
    question: 'Is the electricity cost exact?',
    answer:
      'No, it is an estimate. It depends on the electricity price (a public household average for your country or the tariff you enter), the data your device reports, your region and currency, and how accurate the operating system’s counters are. Treat it as a good order of magnitude, not a bill.',
  },
  {
    id: 'how-ai-works',
    question: 'How does WattByte AI work?',
    answer:
      'When you tap Generate insight, Weekly summary, Monthly summary or Roast me, the app sends only the totals of that period to the WattByte backend, which asks one AI provider for a short explanation. The AI never calculates numbers and the backend does not store the prompt or the answer. Free-form questions are not available yet.',
  },
  {
    id: 'export',
    question: 'Can I export my data?',
    answer:
      'Yes. Settings has Export CSV and Export JSON, which include your daily data, charging sessions and settings. If you use cloud sync, the server can also return a JSON or CSV export of your account.',
  },
];
