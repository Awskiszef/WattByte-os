import type { Metadata } from 'next';
import { CompanyDetails } from '@/components/ui/company-details';
import { PageHeader } from '@/components/ui/page-header';
import { Prose } from '@/components/ui/prose';
import { Section } from '@/components/ui/section';
import { site } from '@/config/site';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Contact',
  description: 'How to reach the WattByte team for support, privacy requests and press.',
  path: '/contact',
});

export default function ContactPage() {
  return (
    <>
      <PageHeader title="Contact." copy="One address for everything. Say what it is about in the subject line and the right person reads it." />
      <Section tight>
        <div className="container-x">
          <Prose>
            <p>
              <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>
            </p>
            <h2>Support</h2>
            <p>Problems with the app, permissions, estimates or your account. See the support page first for the common cases.</p>
            <h2>Privacy requests</h2>
            <p>Access, export or erasure of the data held about your account. Deleting the account from the app is the fastest way to erase everything; write to us if you cannot sign in.</p>
            <h2>Press and partnerships</h2>
            <p>Use the same address with &quot;Press&quot; in the subject.</p>
            <h2>Company details</h2>
            <p>WattByte is operated by {site.company.name}, a sole proprietorship registered in Poland.</p>
          </Prose>
          <CompanyDetails className="mt-6 max-w-[42rem]" />
        </div>
      </Section>
    </>
  );
}
