import Link from "next/link";
import Image from "next/image";
import { ArrowUpRight } from "lucide-react";
import MathBackground from "@/components/MathBackground";

export default function Home() {
  return (
    <div className="relative min-h-screen flex flex-col bg-background font-sans overflow-x-hidden">
      {/* Navigation */}
      <header className="w-full bg-background/90 backdrop-blur-md border-b border-border sticky top-0 z-50">
        <div className="max-w-[1400px] mx-auto px-6 lg:px-10 h-[72px] flex items-center justify-between">
          <div className="flex items-center gap-8">
            <Link href="/" className="flex items-center gap-2">
              <span className="text-xl font-medium tracking-tight text-primary">cauchy</span>
            </Link>
            
            <nav className="hidden lg:flex items-center gap-6 text-[15px] font-medium text-primary">
              <Link href="#product" className="hover:opacity-60 transition-opacity flex items-center gap-1">
                Engine <span className="text-[10px] opacity-50">▼</span>
              </Link>
              <Link href="#solutions" className="hover:opacity-60 transition-opacity flex items-center gap-1">
                Capabilities <span className="text-[10px] opacity-50">▼</span>
              </Link>
              <Link href="https://github.com/jerryjin/cauchy" className="hover:opacity-60 transition-opacity">
                Source
              </Link>
            </nav>
          </div>
          
          <div className="flex items-center gap-6">
            <Link
              href="/download"
              className="bg-accent text-accent-text px-5 py-2.5 rounded-md text-[15px] font-medium hover:bg-accent-hover transition-colors"
            >
              Get Cauchy
            </Link>
          </div>
        </div>
      </header>

      <main className="flex-1 flex flex-col items-center w-full">
        {/* Hero Section */}
        <section className="w-full pt-20 pb-16 px-6 flex flex-col items-center text-center relative overflow-hidden">
          
          {/* Animated 3D Math Grid Background */}
          <MathBackground />
          
          <div className="relative z-10 w-full flex flex-col items-center">
            
            <h1 className="text-[64px] sm:text-[80px] lg:text-[100px] font-medium tracking-[-0.03em] leading-[1.05] text-primary max-w-[1000px] mb-4">
              Intelligence applied. <br/> Localized completely.
            </h1>
            
            <p className="text-[22px] sm:text-[28px] text-secondary max-w-3xl mb-12 font-normal tracking-[-0.01em]">
              Deep reading, code synthesis, and research* — <br className="hidden sm:block"/>computed natively on Apple Silicon.
            </p>
            
            <div className="flex flex-col sm:flex-row items-center gap-4 mb-20">
              <Link
                href="/download"
                className="w-full sm:w-auto h-12 flex items-center justify-center bg-accent text-accent-text px-8 rounded-md text-[16px] font-medium whitespace-nowrap hover:bg-accent-hover transition-colors"
              >
                Download for macOS
              </Link>
              <div className="w-full sm:w-auto h-12 flex items-center justify-center bg-card border border-border text-secondary px-6 rounded-md font-sans font-medium text-[14px]">
                brew install --cask cauchy
              </div>
            </div>

            {/* Hero Image / App Mockup Area */}
            <div className="w-full max-w-[1200px] bg-card rounded-2xl border border-border flex items-center justify-center overflow-hidden relative shadow-2xl">
              <Image src="/app-screenshot.png" width={2400} height={1600} className="w-full h-auto" alt="Cauchy Interface" priority />
            </div>
          </div>
        </section>

        {/* Features Grid */}
        <section className="w-full py-24 sm:py-32 px-6 bg-background relative z-10 border-t border-border">
          <div className="max-w-[1400px] mx-auto">
            
            <div className="mb-16 flex flex-col md:flex-row md:items-end justify-between gap-8">
              <div>
                <h2 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary">
                  The mathematical approach to context.
                </h2>
                <p className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-secondary">
                  Agents mapping your documents natively.
                </p>
              </div>
            </div>

            <div className="flex gap-4 mb-12">
              <Link href="/download" className="bg-accent text-accent-text px-5 py-2.5 rounded-md text-[15px] font-medium hover:bg-accent-hover transition-colors">
                Download App
              </Link>
              <button className="bg-card text-primary px-5 py-2.5 rounded-md text-[15px] font-medium hover:bg-border transition-colors border border-border">
                Read Documentation
              </button>
            </div>

            {/* Grid Layout mimicking Ramp */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              
              {/* Large Card 1 */}
              <div className="bg-card rounded-2xl p-10 min-h-[500px] flex flex-col relative overflow-hidden group border border-border">
                <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center border border-border group-hover:scale-105 transition-transform">
                  <ArrowUpRight className="w-4 h-4 text-primary" />
                </div>
                <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary max-w-[80%] z-10">
                  <span className="text-primary">Lexical mapping</span> that <br/> builds deep connections
                </h3>
                
                {/* Abstract UI Placeholder */}
                <div className="mt-auto bg-background rounded-xl border border-border p-6 w-[90%] mx-auto z-10">
                  <div className="w-1/2 h-4 bg-card mb-4 rounded-sm" />
                  <div className="w-full h-12 bg-card rounded-md mb-2 flex items-center px-4 border border-border/50">
                    <div className="w-3/4 h-3 bg-border rounded-sm" />
                  </div>
                  <div className="w-full h-12 bg-card rounded-md flex items-center px-4 border border-border/50">
                    <div className="w-1/2 h-3 bg-border rounded-sm" />
                  </div>
                </div>
              </div>

              {/* Large Card 2 */}
              <div className="bg-card rounded-2xl p-10 min-h-[500px] flex flex-col relative overflow-hidden group border border-border">
                <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center border border-border group-hover:scale-105 transition-transform">
                  <ArrowUpRight className="w-4 h-4 text-primary" />
                </div>
                <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary max-w-[80%] z-10">
                  <span className="text-primary">Isolated execution</span> ensures <br/> absolute data privacy
                </h3>
                
                {/* Abstract UI Placeholder */}
                <div className="mt-auto bg-background rounded-xl border border-border p-6 w-[90%] mx-auto z-10 translate-x-12">
                   <div className="flex gap-4 items-center">
                     <div className="w-12 h-12 rounded-full border border-border bg-card flex items-center justify-center">
                       <div className="w-4 h-4 bg-accent rounded-sm" />
                     </div>
                     <div className="flex-1 space-y-2.5">
                       <div className="w-full h-2.5 bg-card border border-border/50 rounded-sm" />
                       <div className="w-4/5 h-2.5 bg-card border border-border/50 rounded-sm" />
                       <div className="w-1/2 h-2.5 bg-card border border-border/50 rounded-sm" />
                     </div>
                   </div>
                </div>
              </div>

              {/* Small Card 1 */}
              <div className="bg-card rounded-2xl p-10 min-h-[400px] flex flex-col relative overflow-hidden group border border-border">
                <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center border border-border group-hover:scale-105 transition-transform">
                  <ArrowUpRight className="w-4 h-4 text-primary" />
                </div>
                <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary max-w-[80%] z-10">
                  Semantic retrieval <br/>
                  <span className="text-secondary">eliminates blindspots</span>
                </h3>
              </div>

              {/* Small Card 2 */}
              <div className="bg-card rounded-2xl p-10 min-h-[400px] flex flex-col relative overflow-hidden group border border-border">
                <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center border border-border group-hover:scale-105 transition-transform">
                  <ArrowUpRight className="w-4 h-4 text-primary" />
                </div>
                <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary max-w-[80%] z-10">
                  Contextual prompts <br/>
                  <span className="text-secondary">that adapt instantly</span>
                </h3>
              </div>

            </div>
          </div>
        </section>
        
        {/* Secondary Hero */}
        <section className="w-full py-32 bg-background border-t border-border px-6 text-center flex flex-col items-center">
          <h2 className="text-[48px] sm:text-[64px] font-medium tracking-[-0.03em] leading-[1.1] text-primary max-w-[1000px] mb-2">
            Built on advanced mathematical frameworks.
          </h2>
          <h2 className="text-[48px] sm:text-[64px] font-medium tracking-[-0.03em] leading-[1.1] text-secondary max-w-[1000px] mb-10">
            One engine for the intelligence era.
          </h2>
          <Link href="/download" className="bg-accent text-accent-text px-6 py-3 rounded-md text-[16px] font-medium hover:bg-accent-hover transition-colors mb-24">
            Initialize Cauchy
          </Link>
        </section>
      </main>

      {/* Dark Footer */}
      <footer className="w-full bg-[#1C1917] text-white pt-24 pb-12 px-6">
        <div className="max-w-[1400px] mx-auto">
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-8 mb-24">
            
            {/* Footer Column 1 */}
            <div className="flex flex-col gap-4">
              <span className="text-[13px] font-semibold text-white mb-2">Engine</span>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Architecture</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Lexical Analysis</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Local Models</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Performance</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Releases</Link>
            </div>

            {/* Footer Column 2 */}
            <div className="flex flex-col gap-4">
              <span className="text-[13px] font-semibold text-white mb-2">Capabilities</span>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Document Parsing</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Semantic Search</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Context Generation</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Codebase Indexing</Link>
            </div>

            {/* Footer Column 3 */}
            <div className="flex flex-col gap-4">
              <span className="text-[13px] font-semibold text-white mb-2">Resources</span>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Documentation</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">GitHub Repo</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Issue Tracker</Link>
            </div>
            
            {/* Footer Column 4 */}
            <div className="flex flex-col gap-4">
              <span className="text-[13px] font-semibold text-white mb-2">Project</span>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">About Cauchy</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">License</Link>
              <Link href="#" className="text-[13px] text-[#A8A29E] hover:text-white">Contributing</Link>
            </div>

          </div>
          
          <div className="pt-8 border-t border-[#44403C] flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="flex items-center gap-6 text-[12px] text-[#A8A29E]">
              <Link href="#" className="hover:text-white">Terms of Use</Link>
              <Link href="#" className="hover:text-white">Privacy Policy</Link>
            </div>
            <div className="text-[12px] text-[#A8A29E]">
              Cauchy Open Source
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
