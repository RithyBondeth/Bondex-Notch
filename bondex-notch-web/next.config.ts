import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  /* Stripe session creation and webhook verification run in Vercel's Node.js
     runtime. Images stay unoptimised because the current assets are already
     sized for the page and do not need an extra transformation service. */
  images: { unoptimized: true },

  /* Static hosts vary on whether /features resolves to /features.html or
     /features/index.html. Directories work on all of them. */
  trailingSlash: true,
};

export default nextConfig;
