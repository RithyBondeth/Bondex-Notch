import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  /* The site has no server behaviour, so it builds to plain files in `out/`
     and still deploys by copying a directory to any static host — the same
     deploy story it had before the migration. */
  output: 'export',

  /* `next/image` needs a server to optimise on demand. Nothing on the page
     uses it today; this keeps a static export honest if something does. */
  images: { unoptimized: true },

  /* Static hosts vary on whether /features resolves to /features.html or
     /features/index.html. Directories work on all of them. */
  trailingSlash: true,
};

export default nextConfig;
