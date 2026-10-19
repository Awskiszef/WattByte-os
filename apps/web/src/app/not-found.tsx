import { ButtonLink } from '@/components/ui/button';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';

export default function NotFound() {
  return (
    <Section>
      <div className="container-x">
        <SectionHeading as="h1" title="This page does not exist." copy="The address may have changed, or the page was never here." />
        <div className="mt-8 flex gap-3">
          <ButtonLink href="/">Back to the homepage</ButtonLink>
          <ButtonLink href="/support" variant="secondary">
            Get support
          </ButtonLink>
        </div>
      </div>
    </Section>
  );
}
