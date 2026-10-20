'use client';

import { useId, useState, type FormEvent } from 'react';
import { Button } from '@/components/ui/button';
import { site } from '@/config/site';
import { readCampaign } from '@/lib/campaign';

type State = { status: 'idle' | 'sending' | 'done' | 'closed' | 'error'; message?: string };

export function LaunchListForm() {
  const emailId = useId();
  const platformId = useId();
  const [state, setState] = useState<State>({ status: 'idle' });

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const data = new FormData(form);
    setState({ status: 'sending' });
    try {
      const res = await fetch('/api/launch-list', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: data.get('email'), platform: data.get('platform'), source: 'website', ...readCampaign() }),
      });
      const body = (await res.json().catch(() => null)) as { ok?: boolean; closed?: boolean; error?: string } | null;
      if (body?.closed) {
        setState({ status: 'closed', message: 'The launch list is not open yet. Check back soon.' });
        return;
      }
      if (!res.ok || !body?.ok) {
        setState({ status: 'error', message: body?.error ?? 'Could not add you. Check the address and try again.' });
        return;
      }
      form.reset();
      setState({ status: 'done', message: 'You are on the list. We will write once when WattByte is available.' });
    } catch {
      setState({ status: 'error', message: 'Could not reach the server. Try again in a moment.' });
    }
  }

  return (
    <form onSubmit={onSubmit} className="rounded-xl border border-border bg-bg-elevated p-6 sm:p-7" aria-describedby={`${emailId}-note`}>
      <h2 className="text-lg font-semibold tracking-[-0.01em]">Join the launch list</h2>
      <p id={`${emailId}-note`} className="mt-1 text-sm text-fg-muted">
        One e-mail when WattByte is in the stores. Nothing else, and the address is deleted after that.
      </p>
      <div className="mt-5 grid gap-3 sm:grid-cols-[1fr_auto]">
        <div className="grid gap-1.5">
          <label htmlFor={emailId} className="text-sm font-medium">
            E-mail address
          </label>
          <input
            id={emailId}
            name="email"
            type="email"
            required
            autoComplete="email"
            inputMode="email"
            placeholder="you@example.com"
            className="h-11 rounded-md border border-border bg-bg px-3 text-base text-fg placeholder:text-fg-subtle"
          />
        </div>
        <div className="grid gap-1.5">
          <label htmlFor={platformId} className="text-sm font-medium">
            Platform
          </label>
          <select id={platformId} name="platform" className="h-11 rounded-md border border-border bg-bg px-3 text-base text-fg" defaultValue="both">
            {site.platforms.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
            <option value="both">Both</option>
          </select>
        </div>
      </div>
      <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
        <Button type="submit" size="lg" disabled={state.status === 'sending'}>
          {state.status === 'sending' ? 'Adding you' : 'Notify me at launch'}
        </Button>
        <p role="status" aria-live="polite" className="text-sm text-fg-muted">
          {state.message}
        </p>
      </div>
    </form>
  );
}
