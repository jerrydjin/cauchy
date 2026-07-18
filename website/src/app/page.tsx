import Link from "next/link";
import Image from "next/image";
import { ArrowUpRight } from "lucide-react";
import MathBackground from "@/components/MathBackground";

export default function Home() {
  return (
    <>
      {/* Animated 3D Math Grid Background */}
      <div className="absolute top-0 left-0 w-full h-[150vh] pointer-events-none z-0">
        <MathBackground />
      </div>
      {/* Hero Section */}
      <section className="w-full pt-20 pb-16 px-6 flex flex-col items-center text-center relative z-10">
        
        <div className="relative z-10 w-full flex flex-col items-center">
          
          <h1 className="text-[64px] sm:text-[80px] lg:text-[100px] font-medium tracking-[-0.03em] leading-[1.05] text-primary max-w-[1000px] mb-4">
            A PDF reader that <br className="hidden sm:block"/>talks back.
          </h1>
          
          <p className="text-[22px] sm:text-[28px] text-secondary max-w-3xl mb-12 font-normal tracking-[-0.01em]">
            Built for dense mathematics papers. Highlight <br className="hidden sm:block"/>equations to ask your AI assistant questions.
          </p>
          
          <div className="flex flex-col sm:flex-row items-center gap-4 mb-20">
            <Link
              href="https://github.com/jerrydjin/cauchy/releases/latest/download/Cauchy.dmg"
              className="w-full sm:w-auto h-12 flex items-center justify-center bg-accent text-accent-text px-8 rounded-md text-[16px] font-medium whitespace-nowrap hover:bg-accent-hover transition-colors"
            >
              Download for macOS
            </Link>
            <div className="w-full sm:w-auto h-12 flex items-center justify-center bg-card text-secondary px-6 rounded-md font-sans font-medium text-[14px]">
              brew install --cask cauchy
            </div>
          </div>

          {/* Hero Image / App Mockup Area */}
          <div className="w-full max-w-[1200px] bg-card rounded-3xl flex items-center justify-center overflow-hidden relative">
            <Image src="/app-screenshot.png" width={2400} height={1600} className="w-full h-auto" alt="Cauchy Interface" priority quality={100} />
          </div>
        </div>
      </section>

      {/* Features Grid */}
      <section className="w-full py-24 sm:py-32 px-6 bg-transparent relative z-10">
        <div className="max-w-[1400px] mx-auto">
          
          <div className="mb-16 flex flex-col md:flex-row md:items-end justify-between gap-8">
            <div>
              <h2 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary">
                A reading environment for deep work.
              </h2>
              <p className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-secondary">
                Designed for papers, problem sets, and textbooks.
              </p>
            </div>
          </div>

          <div className="flex gap-4 mb-12">
            <Link href="https://github.com/jerrydjin/cauchy/releases/latest/download/Cauchy.dmg" className="bg-accent text-accent-text px-5 py-2.5 rounded-md text-[15px] font-medium hover:bg-accent-hover transition-colors">
              Download App
            </Link>
            <Link href="/setup" className="bg-card text-primary px-5 py-2.5 rounded-md text-[15px] font-medium hover:bg-black/5 transition-colors">
              Read Documentation
            </Link>
          </div>

          {/* Grid Layout mimicking Ramp */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            
            {/* Large Card 1 */}
            <div className="bg-card rounded-3xl p-12 min-h-[500px] flex flex-col relative overflow-hidden group">
              <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center group-hover:scale-105 transition-transform">
                <ArrowUpRight className="w-4 h-4 text-primary" />
              </div>
              <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary max-w-[80%] z-10 mb-4">
                <span className="text-primary">Highlight & Chat</span><br/> Ask questions directly in context
              </h3>
              <p className="text-[16px] text-secondary z-10 mb-8 max-w-[80%] leading-relaxed">
                Highlight any text, equation, or drag a region to capture a diagram. Cauchy opens a thread directly tied to that spot, so your AI assistant knows exactly what you're looking at.
              </p>
              
              {/* Simple Chat UI Mockup */}
              <div className="mt-auto bg-background rounded-2xl p-6 w-[90%] mx-auto z-10 border border-border/50">
                <div className="w-full flex justify-end mb-4">
                  <div className="bg-accent/20 text-accent-text px-4 py-2 rounded-2xl rounded-tr-none text-sm inline-block max-w-[80%]">
                    Can you explain the proof for Lemma 4.1?
                  </div>
                </div>
                <div className="w-full flex justify-start">
                  <div className="bg-card border border-border/50 px-4 py-3 rounded-2xl rounded-tl-none text-sm inline-block max-w-[90%]">
                    <div className="w-full h-2 bg-border/60 rounded-full mb-2"></div>
                    <div className="w-5/6 h-2 bg-border/60 rounded-full mb-2"></div>
                    <div className="w-4/6 h-2 bg-border/60 rounded-full"></div>
                  </div>
                </div>
              </div>
            </div>

            {/* Large Card 2 */}
            <div className="bg-card rounded-3xl p-12 min-h-[500px] flex flex-col relative overflow-hidden group">
              <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center group-hover:scale-105 transition-transform">
                <ArrowUpRight className="w-4 h-4 text-primary" />
              </div>
              <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary max-w-[80%] z-10 mb-4">
                <span className="text-primary">Reference Previews</span><br/> Never lose your place again
              </h3>
              <p className="text-[16px] text-secondary z-10 mb-8 max-w-[80%] leading-relaxed">
                When an author references "Theorem 2.1" pages later, just hover over it. Cauchy generates an on-device index of all definitions, theorems, and equations, showing you a preview instantly.
              </p>
              
              {/* Abstract Reference Hover Mockup */}
              <div className="mt-auto bg-background rounded-2xl p-6 w-[90%] mx-auto z-10 border border-border/50 translate-x-12">
                 <div className="text-secondary text-sm mb-2 font-serif leading-relaxed">
                   By applying <span className="bg-accent/30 text-accent-text px-1 rounded cursor-pointer border border-accent/50">Theorem 2.1</span> to our matrix...
                 </div>
                 {/* Hover Popover */}
                 <div className="mt-2 bg-card border border-border shadow-sm rounded-xl p-4 w-4/5">
                   <div className="text-xs font-semibold text-primary mb-1 uppercase tracking-wider">Theorem 2.1</div>
                   <div className="w-full h-1.5 bg-border rounded-full mb-1.5"></div>
                   <div className="w-3/4 h-1.5 bg-border rounded-full"></div>
                 </div>
              </div>
            </div>

            {/* Small Card 1 */}
            <div className="bg-card rounded-3xl p-12 min-h-[300px] flex flex-col justify-center relative overflow-hidden group">
              <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center group-hover:scale-105 transition-transform">
                <ArrowUpRight className="w-4 h-4 text-primary" />
              </div>
              <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary mb-3">
                Native LaTeX rendering
              </h3>
              <p className="text-[16px] text-secondary max-w-[90%] leading-relaxed">
                All assistant responses render mathematics natively using SwiftMath, meaning complex equations look perfect and scale beautifully without webviews.
              </p>
            </div>

            {/* Small Card 2 */}
            <div className="bg-card rounded-3xl p-12 min-h-[300px] flex flex-col justify-center relative overflow-hidden group">
              <div className="absolute top-8 right-8 w-8 h-8 bg-background rounded-md flex items-center justify-center group-hover:scale-105 transition-transform">
                <ArrowUpRight className="w-4 h-4 text-primary" />
              </div>
              <h3 className="text-[28px] font-medium tracking-[-0.02em] leading-[1.2] text-primary mb-3">
                On-device OCR for equations
              </h3>
              <p className="text-[16px] text-secondary max-w-[90%] leading-relaxed">
                Drag a box over an equation and Cauchy uses Apple's Vision framework to extract the text, helping the AI understand non-selectable math formulas.
              </p>
            </div>

          </div>
        </div>
      </section>
      
      {/* Integrations & Setup */}
      <section className="w-full py-32 px-6 bg-background relative z-10">
        <div className="max-w-[1400px] mx-auto text-center">
          <h2 className="text-[40px] sm:text-[56px] leading-[1.1] tracking-[-0.03em] font-medium text-primary mb-16">
            Bring your own intelligence.
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 text-left">
            <div className="bg-card p-12 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">Claude Code & Codex</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                Cauchy automatically detects and uses your local CLI authentications. The app runs unsandboxed to seamlessly integrate with your terminal tools.
              </p>
            </div>
            <div className="bg-card p-12 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">Apple Intelligence</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                Run models entirely on-device on macOS 27.0+. Your documents and queries never leave your Apple Silicon Mac.
              </p>
            </div>
            <div className="bg-card p-12 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">Gemini API</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                Just drop in your Gemini API key in the settings to power your document queries directly through Google's models.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Quick FAQ */}
      <section className="w-full py-32 px-6 bg-transparent relative z-10">
        <div className="max-w-[1400px] mx-auto text-center">
          <h2 className="text-[40px] sm:text-[56px] leading-[1.1] tracking-[-0.03em] font-medium text-primary mb-16">
            Frequently Asked Questions
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-[1000px] mx-auto text-left">
            <div className="bg-card p-10 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">What is Cauchy?</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                A native macOS app to open PDF documents, highlight text, and talk to an AI assistant about it. Perfect for dense technical textbooks and papers.
              </p>
            </div>
            <div className="bg-card p-10 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">Where is my data stored?</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                100% locally on your machine in <code className="bg-[#E5E5E5] px-1.5 py-0.5 rounded text-[14px]">~/Library/Application Support/Cauchy/</code>.
              </p>
            </div>
            <div className="bg-card p-10 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">Does it upload my PDFs?</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                No. Cauchy never uploads your documents. If you use a cloud provider like Gemini or Claude, only your query and relevant snippets are sent.
              </p>
            </div>
            <div className="bg-card p-10 rounded-3xl">
              <h3 className="text-2xl font-medium text-primary mb-4">Why unsandboxed?</h3>
              <p className="text-[16px] text-secondary leading-relaxed">
                To utilize your locally installed terminal CLIs (like Claude Code), Cauchy needs to run outside the macOS App Sandbox.
              </p>
            </div>
          </div>
          <div className="mt-12 max-w-[1000px] mx-auto flex justify-center">
            <Link href="/faq" className="bg-accent text-accent-text px-6 py-3 rounded-md text-[16px] font-medium hover:bg-accent-hover transition-colors flex items-center gap-2 w-fit">
              Read all FAQs <ArrowUpRight className="w-4 h-4" />
            </Link>
          </div>
        </div>
      </section>
      
      {/* Secondary Hero */}
      <section className="w-full py-32 bg-background px-6 text-center flex flex-col items-center">
        <h2 className="text-[48px] sm:text-[64px] font-medium tracking-[-0.03em] leading-[1.1] text-primary max-w-[1000px] mb-2">
          Read math papers faster.
        </h2>
        <h2 className="text-[48px] sm:text-[64px] font-medium tracking-[-0.03em] leading-[1.1] text-secondary max-w-[1000px] mb-10">
          Understand proofs better.
        </h2>
        <Link href="https://github.com/jerrydjin/cauchy/releases/latest/download/Cauchy.dmg" className="bg-accent text-accent-text px-6 py-3 rounded-md text-[16px] font-medium hover:bg-accent-hover transition-colors mb-24">
          Download Cauchy
        </Link>
      </section>
    </>
  );
}
