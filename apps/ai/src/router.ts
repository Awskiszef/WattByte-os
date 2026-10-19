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
  readonly now?: () => number;
}

export interface OrderOptions {
  readonly prefer?: AIProviderId;
  readonly exclude?: ReadonlySet<AIProviderId>;
}

export interface FailureInfo {
  /** The provider asked to be left alone for at least this long (HTTP `Retry-After`). */
  readonly retryAfterMs?: number;
}

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
  private readonly routing: Readonly<Record<AITask, readonly AIProviderId[]>>;
  private readonly cooldownMs: number;
  private readonly maxCooldownMs: number;
  private readonly now: () => number;

  constructor(providers: Iterable<AIProvider>, opts: RouterOptions = {}) {
    for (const p of providers) this.providers.set(p.id, p);
    this.routing = opts.routing ?? DEFAULT_ROUTING;
    this.cooldownMs = opts.cooldownMs ?? 60_000;
    this.maxCooldownMs = opts.maxCooldownMs ?? 600_000;
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
    const cooling = configured.filter((p) => this.inCooldown(p.id));
    return [...healthy, ...cooling];
  }

  inCooldown(id: AIProviderId): boolean {
    const until = this.cooldownUntil.get(id);
    return until !== undefined && this.now() < until;
  }

  markFailure(id: AIProviderId, info: FailureInfo = {}): void {
    const count = (this.failures.get(id) ?? 0) + 1;
    this.failures.set(id, count);
    if (this.cooldownMs === 0) return;
    const backoff = this.cooldownMs * 2 ** Math.min(count - 1, 30);
    const wanted = Math.max(backoff, info.retryAfterMs ?? 0);
    this.cooldownUntil.set(id, this.now() + Math.min(wanted, this.maxCooldownMs));
  }

  markSuccess(id: AIProviderId): void {
    this.cooldownUntil.delete(id);
    this.failures.delete(id);
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
