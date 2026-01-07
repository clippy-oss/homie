import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        manrope: ['var(--font-manrope)', 'sans-serif'],
        garamond: ['var(--font-eb-garamond)', 'serif'],
      },
      colors: {
        primary: '#000000',
        secondary: '#ffffff',
        accent: '#333333',
      },
      letterSpacing: {
        wide: '0.1em',
      },
      animation: {
        scroll: 'scroll 25s linear infinite',
        'scroll-slow': 'scroll 30s linear infinite',
      },
      keyframes: {
        scroll: {
          '0%': { transform: 'translateX(0)' },
          '100%': { transform: 'translateX(-50%)' },
        },
      },
    },
  },
  plugins: [],
};

export default config;
