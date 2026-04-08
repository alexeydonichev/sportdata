/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  poweredByHeader: false,
  compress: true,
  
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

  experimental: {
    serverMinification: true,
  },
};

module.exports = nextConfig;
