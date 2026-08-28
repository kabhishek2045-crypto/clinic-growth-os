import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { FlatCompat } from '@eslint/eslintrc';

const compat = new FlatCompat({ baseDirectory: dirname(fileURLToPath(import.meta.url)) });

const config = [
  { ignores: ['.next/**', 'node_modules/**', 'next-env.d.ts'] },
  ...compat.extends('next/core-web-vitals', 'next/typescript'),
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  },
  {
    // The tenant boundary, enforced by tooling rather than by a comment.
    //
    // src/lib/db/tenant.ts used to state that "the ESLint rule in
    // eslint.config.mjs plus code review are what keep it from happening" —
    // and no such rule existed. A security comment asserting a control that is
    // not there is worse than no comment: a reviewer reads it and stops looking.
    //
    // Taking a client straight from the pool skips set_tenant_context, so the
    // query runs with no principal. The helpers fail closed, so it returns
    // nothing rather than leaking — but it is still a bug, and now it is a
    // lint error everywhere except inside the data layer itself.
    files: ['src/**/*.ts', 'src/**/*.tsx'],
    ignores: ['src/lib/db/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: [
            {
              name: '@/lib/db/client',
              message:
                'Do not take a connection from the pool directly. Use withTenant() or withPlatformAdmin() from @/lib/db/tenant.',
            },
            {
              name: 'pg',
              importNames: ['Pool', 'Client'],
              message:
                'Do not open a database connection outside src/lib/db. Use withTenant() from @/lib/db/tenant.',
            },
          ],
          patterns: [
            {
              group: ['**/lib/db/client', './client', '../db/client'],
              message:
                'Do not take a connection from the pool directly. Use withTenant() or withPlatformAdmin() from @/lib/db/tenant.',
            },
          ],
        },
      ],
    },
  },
];

export default config;
