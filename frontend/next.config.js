/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'images.wbstatic.net',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: '*.wbstatic.net',
        pathname: '/**',
      },
    ],
  },
};

module.exports = nextConfig;
