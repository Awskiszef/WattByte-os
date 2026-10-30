import type { Metadata } from 'next';
import Link from 'next/link';
import { PageHeader } from '@/components/ui/page-header';
import { Prose } from '@/components/ui/prose';
import { Section } from '@/components/ui/section';
import { site } from '@/config/site';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Cookie Notice',
  description: 'This website sets no tracking cookies. What it stores in your browser and why.',
  path: '/cookies',
});

export default function CookiesPage() {
  return (
    <>
      <PageHeader title="Cookie notice." copy={`Last updated ${site.legal.cookiesUpdated}. The short version: this website sets no tracking cookies, so there is no banner to click away.`} />
      <Section tight>
        <div className="container-x">
          <Prose>
            <h2 className="!mt-0">What this website stores in your browser</h2>
            <ul>
              <li>
                <strong>Theme preference</strong> (dark or light) in local storage, set only when you use the theme switch. It never leaves your browser.
              </li>
              <li>
                <strong>Campaign tag</strong> in session storage, set only when you arrive through one of our ads or tagged links (the <code>utm_</code> parameters in the address). It is erased when you close the tab and leaves your browser only if you join the launch list.
              </li>
            </ul>
            <h2>What it does not do</h2>
            <ul>
              <li>No analytics, no advertising pixels, no social media embeds, no third-party fonts loaded from external servers.</li>
              <li>No cookies are set by the website itself.</li>
            </ul>
            <h2>The launch list</h2>
            <p>If you submit the launch-list form, the e-mail address and platform you entered, and the campaign tag if you arrived through a tagged link, are saved to a private Google Sheet that we use to send one launch announcement. This is a form submission, not a cookie, and it happens only when you press the button.</p>
            <h2>The app</h2>
            <p>
              The WattByte app uses no cookies and no trackers. What it stores and sends is described in the <Link href="/privacy">privacy policy</Link>.
            </p>
          </Prose>
        </div>
      </Section>
    </>
  );
}
