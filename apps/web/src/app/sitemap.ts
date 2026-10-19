import type { MetadataRoute } from 'next';
import { routes } from '@/config/navigation';
import { site } from '@/config/site';

const priorities: Partial<Record<(typeof routes)[number], number>> = {
  '/': 1,
  '/features': 0.9,
  '/about': 0.8,
  '/ai': 0.8,
  '/download': 0.9,
  '/pricing': 0.7,
  '/faq': 0.6,
};

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date(site.legal.privacyUpdated);
  return routes.map((path) => ({
    url: `${site.url}${path === '/' ? '' : path}`,
    lastModified,
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: priorities[path] ?? 0.5,
  }));
}
