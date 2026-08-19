import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';

const eslintConfig = defineConfig([
  ...nextVitals,
  globalIgnores([
    '.next/**',
    'out/**',
    'build/**',
    'next-env.d.ts',
    '.source/**',
    'components/ai/**',
    'components/accordion.tsx',
    'components/docs-sidebar/**',
    'components/toc/**',
    'layouts/**',
  ]),
]);

export default eslintConfig;
