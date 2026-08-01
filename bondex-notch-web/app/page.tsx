import ContactCta from '@/components/ContactCta';
import Faq from '@/components/Faq';
import FeatureShowcase from '@/components/FeatureShowcase';
import Features from '@/components/Features';
import Hero from '@/components/Hero';
import Performance from '@/components/Performance';
import Pricing from '@/components/Pricing';
import States from '@/components/States';

/* Everything below is a server component apart from the notch bar, the
   wallpaper and the demo — the page ships almost no JavaScript. */

export default function Home() {
  return (
    <main id="main">
      <Hero />
      <FeatureShowcase />
      <Performance />
      <Features />
      <States />
      <Pricing />
      <Faq />
      <ContactCta />
    </main>
  );
}
