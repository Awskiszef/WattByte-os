import type { AIInput } from '../schemas.js';
import { AI_SEVERITIES } from '../schemas.js';
import type { AILocale, AIMode, AITask } from '../types.js';

export interface Prompt {
  readonly system: string;
  readonly user: string;
}

const TASK_GOAL: Record<AITask, string> = {
  insight: 'Write one short, specific observation about this period.',
  weekly_summary: 'Write a short summary of this week.',
  monthly_summary: 'Write a short summary of this month.',
  roast: 'Write a playful, witty roast of these habits.',
};

const MODE_STYLE: Record<AIMode, string> = {
  normal: 'Neutral, clear, factual. No jokes.',
  friendly: 'Warm and encouraging. Light, positive.',
  funny: 'Light humour, one clever line is enough.',
  roast:
    'Witty teasing about the habits shown in the numbers. Never insult the person, ' +
    'never mock intelligence, money, health or appearance. No profanity, no slurs, no threats. ' +
    'It must still feel kind underneath.',
};

const LANGUAGE: Record<AILocale, string> = {
  en: 'Write in English.',
  pl: 'Pisz po polsku, naturalnie, z polskimi znakami.',
};

/** Builds the provider-agnostic prompt. Numbers are quoted, never recomputed. */
export function buildPrompt(task: AITask, mode: AIMode, locale: AILocale, input: AIInput): Prompt {
  const system = [
    'You are WattByte, a phone data and energy companion.',
    'You receive statistics that were already computed. Quote them as given.',
    'Do not calculate, convert, extrapolate or invent any number, unit or price.',
    'If a figure is missing or null, simply do not mention it.',
    'Do not give health, financial or safety advice. Do not mention being an AI.',
    TASK_GOAL[task],
    `Style: ${MODE_STYLE[mode]}`,
    LANGUAGE[locale],
    'Answer with a single JSON object and nothing else, with exactly these keys:',
    '{"title": string (max 80 chars), "message": string (max 600 chars), ' +
      `"tone": "${mode}", "severity": one of ${JSON.stringify(AI_SEVERITIES)}, "emoji": one emoji}`,
  ].join('\n');

  const lines = [
    `period: ${input.period} (${input.periodType})`,
    `mobile data: ${input.mobileDataGb} GB`,
    `wifi data: ${input.wifiDataGb} GB`,
    `total data: ${input.totalDataGb} GB`,
    `charging sessions: ${input.chargingSessions}`,
  ];
  // An unknown figure is stated as unknown, never as a number: the model must not read 0 kWh into a missing capacity.
  if (input.batteryEnergyKwh != null) lines.push(`energy stored in battery: ${input.batteryEnergyKwh} kWh`);
  if (input.wallEnergyKwh != null) lines.push(`energy drawn from the wall (estimated): ${input.wallEnergyKwh} kWh`);
  if (input.electricityCost != null) lines.push(`electricity cost (estimated): ${input.electricityCost} ${input.currency}`);
  if (input.batteryEnergyKwh == null && input.wallEnergyKwh == null && input.electricityCost == null) {
    lines.push('energy and cost: unknown (the battery capacity is not set); say nothing about energy or cost');
  }
  if (input.previousPeriodChangePercent != null) {
    lines.push(`change vs previous ${input.periodType}: ${input.previousPeriodChangePercent}%`);
  }
  if (input.wifiSharePercent != null) lines.push(`wifi share of total data: ${input.wifiSharePercent}%`);
  if (input.averageSessionMah != null) lines.push(`average charge per session: ${input.averageSessionMah} mAh`);

  return { system, user: lines.join('\n') };
}
