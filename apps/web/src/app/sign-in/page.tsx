import type { Metadata } from 'next';
import { ButtonLink } from '@/components/ui/button';
import { PageHeader } from '@/components/ui/page-header';
import { Section } from '@/components/ui/section';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Sign in',
  description: 'WattByte accounts are created and used inside the app. There is no web dashboard.',
  path: '/sign-in',
});

export default function SignInPage() {
  return (
    <>
      <PageHeader
        title="Sign in from the app."
        copy="Your WattByte account lives in the app on your phone: that is where you create it, sign in, switch cloud sync on or off and delete it. There is no web dashboard, so there is nothing to sign in to here."
      >
        <ButtonLink href="/download">Get the app</ButtonLink>
        <ButtonLink href="/support" variant="secondary">
          Trouble signing in
        </ButtonLink>
      </PageHeader>
      <Section tight>
        <div className="container-x">
          <ul className="max-w-[40rem] space-y-3 text-sm text-fg-muted">
            <li>No account is needed to see your own usage; the dashboard works offline.</li>
            <li>An account is needed for cloud sync and AI insights, because the daily AI allowance is counted per account.</li>
            <li>Sign in with Apple and Google are prepared in the backend but not switched on yet; e-mail and password work today.</li>
          </ul>
        </div>
      </Section>
    </>
  );
}
