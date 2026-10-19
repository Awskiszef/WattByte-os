import type { Metadata } from 'next';
import { site } from '@/config/site';

type PageMeta = {
  title: string;
  description: string;
  /** Path starting with "/" */
  path: string;
  /** Use the exact title instead of the "<title> — WattByte" template. */
  absoluteTitle?: boolean;
};

export function absoluteUrl(path: string): string {
  return `${site.url}${path === '/' ? '' : path}` || site.url;
}

/** Shared metadata for a page: canonical, Open Graph and Twitter card. */
export function pageMetadata({ title, description, path, absoluteTitle }: PageMeta): Metadata {
  const url = absoluteUrl(path);
  const fullTitle = absoluteTitle ? title : `${title} — ${site.name}`;
  const image = { url: absoluteUrl('/opengraph-image'), width: 1200, height: 630, alt: `${site.name}: ${site.tagline}` };
  return {
    title: absoluteTitle ? { absolute: title } : title,
    description,
    alternates: { canonical: url },
    openGraph: {
      type: 'website',
      siteName: site.name,
      title: fullTitle,
      description,
      url,
      locale: 'en_US',
      images: [image],
    },
    twitter: {
      card: 'summary_large_image',
      title: fullTitle,
      description,
      images: [image.url],
    },
  };
}

export function organizationJsonLd() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: site.name,
    url: site.url,
    logo: absoluteUrl('/icon.svg'),
    email: site.supportEmail,
  };
}

export function softwareApplicationJsonLd() {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: site.name,
    url: site.url,
    description: site.description,
    applicationCategory: 'UtilitiesApplication',
    operatingSystem: 'iOS, Android',
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR', description: 'Free plan' },
  };
}

export function faqJsonLd(items: ReadonlyArray<{ question: string; answer: string }>) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: items.map((item) => ({
      '@type': 'Question',
      name: item.question,
      acceptedAnswer: { '@type': 'Answer', text: item.answer },
    })),
  };
}
