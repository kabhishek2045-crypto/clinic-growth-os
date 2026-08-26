import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // A lockfile in the home directory was being inferred as the workspace root.
  outputFileTracingRoot: dirname(fileURLToPath(import.meta.url)),
  typescript: { ignoreBuildErrors: false },
  eslint: { ignoreDuringBuilds: false },
  // MASTER_PROMPT §38 — secure headers. CSP is added in M3 alongside branding,
  // because the clinic-branding CSS-variable pipeline determines what it must allow.
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'X-Frame-Options', value: 'DENY' },
          {
            key: 'Strict-Transport-Security',
            value: 'max-age=63072000; includeSubDomains; preload',
          },
        ],
      },
    ];
  },
};

export default nextConfig;
