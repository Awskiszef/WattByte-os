import type { Metadata } from 'next';
import { LaunchListForm } from '@/components/sections/launch-list-form';
import { StoreBadges } from '@/components/sections/store-badges';
import { PageHeader } from '@/components/ui/page-header';
import { Section } from '@/components/ui/section';
import { site } from '@/config/site';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Download',
  description: 'Get WattByte for iPhone and Android. The app is in preparation for the stores; join the launch list to be told when it is available.',
  path: '/download',
});

export default function DownloadPage() {
  const live = Boolean(site.stores.appStore || site.stores.googlePlay);
  return (
    <>
      <PageHeader
        title={live ? 'Get WattByte.' : 'WattByte is almost in the stores.'}
        copy={
          live
            ? 'Install it from the store for your phone. No account is needed to see your own numbers.'
            : 'The app is being prepared for the App Store and Google Play. Leave your address and we will tell you once, when it is available.'
        }
      />
      <Section tight>
        <div className="container-x grid gap-8 lg:grid-cols-[1fr_1fr] lg:items-start">
          <div className="rounded-xl border border-border p-6 sm:p-7">
            <h2 className="text-lg font-semibold tracking-[-0.01em]">Platforms</h2>
            <ul className="mt-4 divide-y divide-border">
              {site.platforms.map((p) => (
                <li key={p.id} className="flex items-center justify-between py-3 text-sm">
                  <span className="font-medium">{p.name}</span>
                  <span className="text-fg-muted">{p.requirement}</span>
                </li>
              ))}
            </ul>
            <StoreBadges className="mt-6 justify-start" />
            <p className="mt-4 text-xs text-fg-subtle">Available in {site.languages.join(' and ')}.</p>
          </div>
          <LaunchListForm />
        </div>
      </Section>
    </>
  );
}
