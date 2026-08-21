import './globals.css';

export const metadata = {
  title: 'Heph',
  description: 'Lua obfuscator which prevents malicious attempts of dumping',
};

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: 'cover',
  themeColor: '#11111b',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body className="grid-background min-h-screen">
        {children}
      </body>
    </html>
  );
}
