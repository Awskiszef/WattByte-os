import type { Metadata } from 'next';
import Link from 'next/link';
import { CompanyDetails } from '@/components/ui/company-details';
import { PageHeader } from '@/components/ui/page-header';
import { Prose } from '@/components/ui/prose';
import { Section } from '@/components/ui/section';
import { site } from '@/config/site';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Privacy Policy',
  description: 'What WattByte stores on your phone, what leaves it only when you choose, how long it is kept and how to delete it.',
  path: '/privacy',
});

export default function PrivacyPage() {
  return (
    <>
      <PageHeader title="Privacy Policy." copy={`Last updated ${site.legal.privacyUpdated}. This policy describes what the WattByte app and this website actually do with data.`} />
      <Section tight>
        <div className="container-x">
          <Prose>
            <h2 className="!mt-0">The short version</h2>
            <ul>
              <li>Your usage data is stored on your phone, in the app&apos;s private storage.</li>
              <li>Nothing is uploaded unless you create an account and switch cloud sync on. Sync is off by default.</li>
              <li>When sync is on, one row per day is uploaded: bytes, energy, charging sessions and estimated cost. Never raw samples, never per-app usage.</li>
              <li>There is no advertising SDK, no analytics SDK, no crash-reporting service and no tracker in the app or on this website.</li>
              <li>Your data is not sold or shared with advertisers.</li>
              <li>You can export everything and you can delete the account, with everything attached to it, from inside the app.</li>
            </ul>

            <h2>1. Who is responsible</h2>
            <p>
              The controller of your data is {site.company.name}, {site.company.address.street}, {site.company.address.postalCode}{' '}
              {site.company.address.city}, {site.company.address.country} (NIP {site.company.nip}, REGON {site.company.regon}), which operates the WattByte app
              and the website at {site.url}. For any question about this policy or your data, write to{' '}
              <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>.
            </p>
            <CompanyDetails className="mb-6" />

            <h2>2. Data kept on your phone</h2>
            <p>The app stores these in its private storage, which other apps cannot read:</p>
            <ul>
              <li>daily mobile and Wi-Fi bytes (download and upload), used for statistics;</li>
              <li>battery level, charging state, charge and energy counters and voltage samples, used to build charging sessions;</li>
              <li>charging sessions (start, end, levels, charge and energy added), used for history, energy and cost;</li>
              <li>settings: electricity price, currency, charging efficiency, design battery capacity and its source, theme, notification choices, the cloud sync switch;</li>
              <li>your region as a country code taken from the device region or locale setting, and your device model code (for example &quot;iPhone16,1&quot; or &quot;Pixel 8&quot;), used for the default currency and the battery capacity lookup. No location, no serial number;</li>
              <li>on Android, an estimate of your battery&apos;s full-charge capacity derived from the charge counter, with a confidence level;</li>
              <li>a random installation id and a queue of per-day totals, used only if you switch cloud sync on.</li>
            </ul>
            <p>Per-app data usage on Android is read from the system when you open the &quot;Data by app&quot; screen and is not stored. Android app backup is switched off, so this data is not copied to Google or to other devices.</p>

            <h2>3. Data that leaves your phone, and only if you choose</h2>
            <p>Cloud features exist only after you create an account. Then:</p>
            <ul>
              <li>
                <strong>Account:</strong> your e-mail address, a password hash (the password itself is never stored) and an optional display name, sent when you create the account or sign in.
              </li>
              <li>
                <strong>Device registration:</strong> the random installation id, the platform (iOS or Android), the model name and model code, the design battery capacity of the model with its source, and on Android the estimated full-charge capacity with its source and confidence. No IMEI, MAC address, advertising id or serial number.
              </li>
              <li>
                <strong>Daily totals (only with cloud sync on):</strong> one row per day with mobile bytes, Wi-Fi bytes, battery and wall energy in Wh, number of charging sessions, estimated cost, currency and two &quot;estimated&quot; flags.
              </li>
              <li>
                <strong>Account settings:</strong> country, currency, electricity price mode and a manual price if you set one, with the origin of each value.
              </li>
              <li>
                <strong>AI requests (only when you tap Generate insight, Weekly summary, Monthly summary or Roast me):</strong> the totals of that period in GB, kWh, sessions and estimated cost. See section 5.
              </li>
            </ul>
            <p>Never uploaded: raw battery samples, session timestamps, per-app usage, your electricity price or efficiency settings, notification choices.</p>
            <p>The app talks to the WattByte backend over HTTPS only. Sign-in tokens are kept in the iOS Keychain or the Android Keystore-backed storage, never in plain preferences.</p>

            <h2>4. Why we process this data</h2>
            <p>To provide the features you use: statistics on your phone, an account you asked for, cloud sync you switched on, and AI explanations you requested. We do not use it for advertising, profiling or sale to third parties.</p>

            <h2>5. AI explanations</h2>
            <p>
              An AI request contains only the period totals listed above. The backend validates the request against a strict schema and rejects anything else, such as an e-mail address, user id, device id or token, before any prompt is built. The backend then asks one AI provider for a short explanation. The providers that may receive the totals are OpenAI, Anthropic, Google and xAI; the backend picks one per request and, after an outage or a rate limit, may send the same request to one other provider. OpenAI and xAI are asked not to retain the request. The backend stores, per generation, the task, provider, model, token counts, estimated cost, latency and time. It does not store the prompt or the answer.
            </p>

            <h2>6. This website</h2>
            <p>
              This website sets no tracking cookies and loads no analytics. Your theme choice is kept in your browser&apos;s local storage. If you join the launch list, your e-mail address and chosen platform are forwarded to our mailing service and used for one announcement. If you reached the site through one of our ads or tagged links, the campaign tag of that link (the <code>utm_source</code>, <code>utm_medium</code>, <code>utm_campaign</code> and <code>utm_content</code> parameters, for example &quot;tiktok&quot; or &quot;launch-video&quot;) is stored with the sign-up, so we can tell which ad worked. It is deleted together with the address. See the <Link href="/cookies">cookie notice</Link>.
            </p>

            <h2>7. Retention</h2>
            <ul>
              <li>Data on your phone: until you reset statistics in Settings or uninstall the app.</li>
              <li>Account and synced rows: until you delete the account. Deleting the account removes it and, in one step, its sessions, devices, daily rows, AI usage records and quota counters.</li>
              <li>Switching cloud sync off stops uploads immediately; rows already uploaded stay until the account is deleted.</li>
              <li>A table of daily totals per AI provider (cost and number of answers, with no user id) is kept for spend limits and is not personal data.</li>
            </ul>

            <h2>8. Your rights and controls</h2>
            <ul>
              <li>Export: Settings has Export CSV and Export JSON for everything on your phone. With an account, the backend can return a JSON or CSV export of what it holds.</li>
              <li>Erase: Reset Statistics erases the phone copy; Delete account (Account screen) erases the cloud copy with the account.</li>
              <li>Correct: every detected setting (region, currency, price, battery capacity) can be changed by hand in Settings.</li>
              <li>Depending on where you live you may have further rights, for example under the GDPR, including the right to complain to a supervisory authority. Write to us first and we will help.</li>
            </ul>

            <h2>9. Permissions</h2>
            <ul>
              <li>Android: Usage access (for mobile, Wi-Fi and per-app totals), notifications (optional alerts) and internet (account, sync and AI).</li>
              <li>iOS: none beyond background refresh.</li>
            </ul>
            <p>Each permission is explained on screen before the system prompt, and the app works without the optional ones.</p>

            <h2>10. Children</h2>
            <p>WattByte is not directed at children under 16 and we do not knowingly collect their data.</p>

            <h2>11. Changes</h2>
            <p>When this policy changes, the date at the top changes with it. Material changes are announced in the app before they take effect.</p>
          </Prose>
        </div>
      </Section>
    </>
  );
}
