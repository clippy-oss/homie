import type { Metadata } from 'next';
import { Manrope, EB_Garamond } from 'next/font/google';
import './globals.css';

const manrope = Manrope({
  subsets: ['latin'],
  variable: '--font-manrope',
  display: 'swap',
});

const ebGaramond = EB_Garamond({
  subsets: ['latin'],
  variable: '--font-eb-garamond',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Clippy - Message Intelligence',
  description: 'Built to make productivity aesthetic and fun',
  icons: {
    icon: '/assets/Group 68.png',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${manrope.variable} ${ebGaramond.variable}`}>
      <body className="font-manrope bg-white text-black min-h-screen flex flex-col">
        {children}
      </body>
    </html>
  );
}
