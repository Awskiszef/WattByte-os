import type { AIProvider, AIProviderId, AITask } from './types.js';

/** Preferred provider order per task; the first healthy one answers. */
export const DEFAULT_ROUTING: Readonly<Record<AITask, readonly AIProviderId[]>> = {
  insight: ['google', 'openai', 'xai', 'anthropic'],
  weekly_summary: ['openai', 'google', 'anthropic', 'xai'],
  monthly_summary: ['anthropic', 'openai', 'google', 'xai'],
  roast: ['xai', 'openai', 'anthropic', 'google'],
};

export interface RouterOptions {
  readonly routing?: Readonly<Record<AITask, readonly AIProviderId[]>>;
  /**
   * A provider that failed is demoted behind the healthy ones for this long
   * (circuit breaker). Consecutive failures double it. 0 disables the breaker.
   */
  readonly cooldownMs?: number;
  /** Upper bound for the doubled cooldown and for a provider's `Retry-After`. Default 10 minutes. */
  readonly maxCooldownMs?: number;
  /**
   * While a provider cools down, ONE request per this interval is let through to it as a probe (and only when no
   * healthy provider is left); every other request skips it at once instead of paying for another failure. Default 5 s.
   */
  readonly probeIntervalMs?: number;
  readonly now?: () => number;
}

export interface OrderOptions {
  readonly prefer?: AIProviderId;
  readonly exclude?: ReadonlySet<AIProviderId>;
}

export interface FailureInfo {
  /** The provider asked to be left alone for at least this long (HTTP `Retry-After`). */
  readonly retryAfterMs?: number;
  /**
   * The provider answered but the answer was unusable (refusal, bad output). That is a property of one answer, not of
   * the provider's availability: it counts against the provider only when it is the rule rather than the exception
   * (more than `CONTENT_FAILURE_RATE` of its last `CONTENT_WINDOW` answers), so a burst of long Polish answers cannot
   * park a healthy provider (D-08).
   */
  readonly content?: boolean;
}

const CONTENT_WINDOW = 10;
const CONTENT_MIN_SAMPLES = 6;
const CONTENT_FAILURE_RATE = 0.6;

export interface ProviderHealth {
  readonly id: AIProviderId;
  readonly inCooldown: boolean;
  /** Milliseconds until the provider is considered healthy again; 0 when it is. */
  readonly retryInMs: number;
  readonly consecutiveFailures: number;
}

/**
 * Picks providers for a task. Only configured providers count; a provider
 * that just failed sits behind the healthy ones for `cooldownMs` (doubling
 * with each consecutive failure up to `maxCooldownMs`, or longer if the
 * provider sent `Retry-After`) so fallbacks do not keep hammering a dead
 * endpoint. A cooling provider is still tried as a last resort, so a total
 * outage never turns into "no provider". Providers are tried one at a time,
 * never in parallel.
 */
export class ProviderRouter {
  private readonly providers = new Map<AIProviderId, AIProvider>();
  private readonly cooldownUntil = new Map<AIProviderId, number>();
  private readonly failures = new Map<AIProviderId, number>();
  /** Last outcomes per provider: true = an unusable answer, false = a good one. */
  private readonly recent = new Map<AIProviderId, boolean[]>();
  private readonly lastProbe = new Map<AIProviderId, number>();
  private readonly probeIntervalMs: number;
  private readonly routing: Readonly<Record<AITask, readonly AIProviderId[]>>;
  private readonly cooldownMs: number;
  private readonly maxCooldownMs: number;
  private readonly now: () => number;

  constructor(providers: Iterable<AIProvider>, opts: RouterOptions = {}) {
    for (const p of providers) this.providers.set(p.id, p);
    this.routing = opts.routing ?? DEFAULT_ROUTING;
    this.cooldownMs = opts.cooldownMs ?? 60_000;
    this.maxCooldownMs = opts.maxCooldownMs ?? 600_000;
    this.probeIntervalMs = opts.probeIntervalMs ?? 5_000;
    this.now = opts.now ?? Date.now;
    if (!Number.isFinite(this.cooldownMs) || this.cooldownMs < 0) throw new RangeError('cooldownMs must be a finite number >= 0');
    if (!Number.isFinite(this.maxCooldownMs) || this.maxCooldownMs < 0) throw new RangeError('maxCooldownMs must be a finite number >= 0');
  }

  get configured(): AIProviderId[] {
    return [...this.providers.keys()];
  }

  /**
   * Candidates in order: healthy first, then cooling-down ones as a last resort. `prefer` (the default
   * provider, or the one a backend caller asked for) goes first among the providers of the same health;
   * a preferred provider that is cooling down still sits behind the healthy ones, so a dead default
   * does not take every request with it. `exclude` removes providers outright (a spent budget).
   */
  order(task: AITask, opts: OrderOptions = {}): AIProvider[] {
    const { prefer, exclude } = opts;
    const ids = this.routing[task].filter((id) => !exclude?.has(id));
    // A preferred provider outside the task's routing table is still a valid choice when it is configured.
    if (prefer && !exclude?.has(prefer) && !ids.includes(prefer)) ids.push(prefer);
    if (prefer) ids.sort((a, b) => Number(b === prefer) - Number(a === prefer));
    const configured = ids.map((id) => this.providers.get(id)).filter((p): p is AIProvider => !!p);
    const healthy = configured.filter((p) => !this.inCooldown(p.id));
    // A cooling provider is a last resort, and then only as a probe: without this every request during an outage
    // would pay for (and wait on) another failed call, and a recovering provider would be hit by all of them at once.
    const probes = healthy.length > 0 ? [] : configured.filter((p) => this.inCooldown(p.id) && this.grantProbe(p.id));
    return [...healthy, ...probes];
  }

  /** True once per `probeIntervalMs` for a cooling provider. */
  private grantProbe(id: AIProviderId): boolean {
    const now = this.now();
    const last = this.lastProbe.get(id);
    if (last !== undefined && now - last < this.probeIntervalMs) return false;
    this.lastProbe.set(id, now);
    return true;
  }

  /** Providers that are configured but cooling down, whatever `order` returned; the gateway uses it to tell "all cooling" from "none configured". */
  get coolingDown(): AIProviderId[] {
    return [...this.providers.keys()].filter((id) => this.inCooldown(id));
  }

  inCooldown(id: AIProviderId): boolean {
    const until = this.cooldownUntil.get(id);
    return until !== undefined && this.now() < until;
  }

  markFailure(id: AIProviderId, info: FailureInfo = {}): void {
    if (info.content) {
      const window = this.pushOutcome(id, true);
      const bad = window.filter(Boolean).length;
      // An occasional unusable answer is not an outage: the provider keeps its place until it is the rule.
      if (window.length < CONTENT_MIN_SAMPLES || bad / window.length <= CONTENT_FAILURE_RATE) return;
    } else {
      this.pushOutcome(id, false);
    }
    const count = (this.failures.get(id) ?? 0) + 1;
    this.failures.set(id, count);
    if (this.cooldownMs === 0) return;
    const backoff = this.cooldownMs * 2 ** Math.min(count - 1, 30);
    const wanted = Math.max(backoff, info.retryAfterMs ?? 0);
    this.cooldownUntil.set(id, this.now() + Math.min(wanted, this.maxCooldownMs));
  }

  markSuccess(id: AIProviderId): void {
    this.pushOutcome(id, false);
    this.cooldownUntil.delete(id);
    this.failures.delete(id);
    this.lastProbe.delete(id);
  }

  private pushOutcome(id: AIProviderId, unusable: boolean): boolean[] {
    const window = this.recent.get(id) ?? [];
    window.push(unusable);
    if (window.length > CONTENT_WINDOW) window.shift();
    this.recent.set(id, window);
    return window;
  }

  provider(id: AIProviderId): AIProvider | undefined {
    return this.providers.get(id);
  }

  /** Point-in-time view for health endpoints and tests. */
  health(): ProviderHealth[] {
    return [...this.providers.keys()].map((id) => ({
      id,
      inCooldown: this.inCooldown(id),
      retryInMs: Math.max(0, (this.cooldownUntil.get(id) ?? 0) - this.now()),
      consecutiveFailures: this.failures.get(id) ?? 0,
    }));
  }
}
