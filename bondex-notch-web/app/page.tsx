import DownloadCta from '@/components/DownloadCta';
import Faq from '@/components/Faq';
import FeatureShowcase from '@/components/FeatureShowcase';
import Features from '@/components/Features';
import Hero from '@/components/Hero';
import Pricing from '@/components/Pricing';
import States from '@/components/States';

/* Everything below is a server component apart from the notch bar, the
   wallpaper and the demo — the page ships almost no JavaScript. */

export default function Home() {
  return (
    <main id="main">
      <Hero />
      <FeatureShowcase />
      <Features />
      <States />
      <Pricing />
      <Faq />
      <DownloadCta />
    </main>
  );
}
