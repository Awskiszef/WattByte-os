import { Apple, Play } from 'lucide-react';
import { site } from '@/config/site';
import { cn } from '@/lib/cn';

type Store = { id: 'appStore' | 'googlePlay'; name: string; line: string; Icon: typeof Apple };

const stores: Store[] = [
  { id: 'appStore', name: 'App Store', line: 'Download on the', Icon: Apple },
  { id: 'googlePlay', name: 'Google Play', line: 'Get it on', Icon: Play },
];

/**
 * App Store and Google Play badges. Until `site.stores` holds a real URL each
 * badge is a labelled placeholder, not a link to nowhere.
 */
export function StoreBadges({ className }: { className?: string }) {
  return (
    <div className={cn('flex flex-wrap items-center justify-center gap-3', className)}>
      {stores.map(({ id, name, line, Icon }) => {
        const href = site.stores[id];
        const inner = (
          <>
            <Icon className="h-6 w-6" aria-hidden="true" />
            <span className="text-left leading-tight">
              <span className="block text-[10px] text-fg-subtle">{href ? line : 'Coming soon on the'}</span>
              <span className="block text-sm font-semibold">{name}</span>
            </span>
          </>
        );
        const cls = 'inline-flex h-12 min-w-[10.5rem] items-center gap-2.5 rounded-md border px-3.5';
        return href ? (
          <a key={id} href={href} className={cn(cls, 'border-fg bg-fg text-bg')} rel="noopener">
            {inner}
          </a>
        ) : (
          <span key={id} className={cn(cls, 'border-dashed border-border-strong text-fg-muted')} aria-label={`${name}: coming soon`}>
            {inner}
          </span>
        );
      })}
    </div>
  );
}
