/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  images: {
    formats: ['image/avif', 'image/webp'],
  },

  async rewrites() {
    return [
      {
        source: '/',
        destination: '/legacy/index.html',
      },
      {
        source: '/legacy/inspiration',
        destination: '/legacy/inspiration.html',
      },
      {
        source: '/download',
        destination: '/download.html',
      },
      {
        source: '/privacy',
        destination: '/privacy.html',
      },
    ];
  },
};

module.exports = nextConfig;
