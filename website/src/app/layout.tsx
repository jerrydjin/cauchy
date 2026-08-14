import type { Metadata } from "next";
import { Manrope, Geist_Mono } from "next/font/google";
import "./globals.css";
import Header from "@/components/Header";
import Footer from "@/components/Footer";

const manrope = Manrope({
  variable: "--font-manrope",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const SITE_URL = "https://cauchy-wine.vercel.app";
const DESCRIPTION =
  "A native macOS PDF reader for mathematics. Highlight a theorem, ask about it, and get answers with real LaTeX — powered by Apple Intelligence on-device, your Claude Code, Codex or Antigravity CLI, or a Gemini key.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Cauchy — a PDF reader that talks back",
  description: DESCRIPTION,
  applicationName: "Cauchy",
  keywords: [
    "PDF reader",
    "macOS",
    "mathematics",
    "LaTeX",
    "Apple Intelligence",
    "Claude Code",
    "Codex",
    "Gemini",
    "papers",
    "theorems",
  ],
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Cauchy",
    title: "Cauchy — a PDF reader that talks back",
    description: DESCRIPTION,
    images: [{ url: "/app-screenshot.png", width: 2400, height: 1600, alt: "Cauchy reading a mathematics paper" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Cauchy — a PDF reader that talks back",
    description: DESCRIPTION,
    images: ["/app-screenshot.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${manrope.variable} ${geistMono.variable} h-full antialiased scroll-smooth`}
    >
      <body className="min-h-full flex flex-col bg-background text-foreground font-sans selection:bg-accent selection:text-foreground">
        <Header />
        <main className="flex-1 flex flex-col items-center w-full relative">
          {children}
        </main>
        <Footer />
      </body>
    </html>
  );
}
