import type { Metadata } from 'next';
import './globals.css';

// §14 — per-tenant metadata, title, and favicon replace these in M3, resolved
// from the verified request host rather than anything the client sends.
export const metadata: Metadata = {
  title: 'Clinic Growth OS',
  description: 'Multi-tenant clinic management and growth platform',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-white text-slate-900 antialiased">{children}</body>
    </html>
  );
}
