/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: {
    serverComponentsExternalPackages: ['child_process'],
    outputFileTracingIncludes: {
      '/api/obfuscate': [
        './lua-staging/**',
        './lua/**',
      ],
    },
  },
};

module.exports = nextConfig;
