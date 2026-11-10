import ContactCta from '@/components/ContactCta';
import Faq, { faqJsonLd } from '@/components/Faq';
import FeatureShowcase from '@/components/FeatureShowcase';
import Features from '@/components/Features';
import Hero from '@/components/Hero';
import Performance from '@/components/Performance';
import Pricing from '@/components/Pricing';
import States from '@/components/States';
import { serializeJsonLd, softwareApplicationJsonLd, websiteJsonLd } from '@/lib/seo';

/* Everything below is a server component apart from the notch bar, the
   wallpaper and the demo — the page ships almost no JavaScript. */

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: serializeJsonLd([
            websiteJsonLd,
            softwareApplicationJsonLd,
            faqJsonLd,
          ]),
        }}
      />
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
    </>
  );
}
