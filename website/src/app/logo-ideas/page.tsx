import React from "react";
import Link from "next/link";

export default function LogoIdeas() {
  return (
    <div className="min-h-screen bg-background text-primary p-12">
      <div className="max-w-[1000px] mx-auto">
        <div className="mb-12 flex items-center justify-between">
          <div>
            <h1 className="text-[40px] font-medium tracking-[-0.02em] leading-[1.2]">
              Logo Concepts
            </h1>
            <p className="text-secondary mt-2 text-lg">
              Explorations for the Cauchy brand identity.
            </p>
          </div>
          <Link 
            href="/" 
            className="text-sm font-medium border border-border px-5 py-2.5 rounded-full hover:bg-card transition-colors"
          >
            &larr; Back to Home
          </Link>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          
          {/* Concept 1: The Analytic C */}
          <div className="bg-card border border-border/50 rounded-3xl p-10 flex flex-col items-center text-center group">
            <div className="w-32 h-32 bg-background border border-border rounded-3xl flex items-center justify-center mb-8 transition-transform group-hover:scale-105">
              <svg width="64" height="64" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M 80 25 A 35 35 0 1 0 80 75" stroke="currentColor" strokeWidth="10" strokeLinecap="round" />
                <circle cx="65" cy="50" r="10" fill="var(--color-accent)" />
              </svg>
            </div>
            <h3 className="text-2xl font-medium mb-3">The Analytic 'C'</h3>
            <p className="text-secondary text-[15px] leading-relaxed max-w-[80%]">
              A geometric 'C' constructed from a smooth curve, representing mathematical analysis. The beige node represents the point of intelligence or focus.
            </p>
          </div>

          {/* Concept 2: Cauchy Sequence */}
          <div className="bg-card border border-border/50 rounded-3xl p-10 flex flex-col items-center text-center group">
            <div className="w-32 h-32 bg-background border border-border rounded-3xl flex items-center justify-center mb-8 transition-transform group-hover:scale-105">
              <svg width="64" height="64" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                <circle cx="20" cy="50" r="10" fill="currentColor" />
                <circle cx="48" cy="50" r="7" fill="currentColor" />
                <circle cx="68" cy="50" r="5" fill="currentColor" />
                <circle cx="82" cy="50" r="3.5" fill="var(--color-accent)" />
                <circle cx="92" cy="50" r="2" fill="var(--color-accent)" opacity="0.5"/>
              </svg>
            </div>
            <h3 className="text-2xl font-medium mb-3">The Sequence</h3>
            <p className="text-secondary text-[15px] leading-relaxed max-w-[80%]">
              A visual representation of a Cauchy sequence converging to a limit. It symbolizes distilling large, complex documents into core insights.
            </p>
          </div>

          {/* Concept 3: Document + Integral */}
          <div className="bg-card border border-border/50 rounded-3xl p-10 flex flex-col items-center text-center group">
            <div className="w-32 h-32 bg-background border border-border rounded-3xl flex items-center justify-center mb-8 transition-transform group-hover:scale-105">
              <svg width="64" height="64" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                <rect x="25" y="15" width="50" height="70" rx="8" stroke="currentColor" strokeWidth="8" />
                <path d="M 60 30 Q 30 50, 60 70" stroke="var(--color-accent)" strokeWidth="8" strokeLinecap="round" fill="none"/>
              </svg>
            </div>
            <h3 className="text-2xl font-medium mb-3">The Integral Document</h3>
            <p className="text-secondary text-[15px] leading-relaxed max-w-[80%]">
              Combines the classic document aspect ratio with a sweeping curve reminiscent of an integral sign or a 'C', highlighting mathematical capabilities.
            </p>
          </div>

          {/* Concept 4: The Knowledge Prism */}
          <div className="bg-card border border-border/50 rounded-3xl p-10 flex flex-col items-center text-center group">
            <div className="w-32 h-32 bg-background border border-border rounded-3xl flex items-center justify-center mb-8 transition-transform group-hover:scale-105">
              <svg width="64" height="64" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M50 15 L85 35 L85 75 L50 95 L15 75 L15 35 Z" stroke="currentColor" strokeWidth="8" strokeLinejoin="round"/>
                <path d="M15 35 L50 55 L85 35" stroke="currentColor" strokeWidth="8" strokeLinejoin="round"/>
                <path d="M50 55 L50 95" stroke="currentColor" strokeWidth="8" strokeLinejoin="round"/>
                <circle cx="50" cy="55" r="8" fill="var(--color-accent)" />
              </svg>
            </div>
            <h3 className="text-2xl font-medium mb-3">The Knowledge Prism</h3>
            <p className="text-secondary text-[15px] leading-relaxed max-w-[80%]">
              A geometric, structural approach representing complex intelligence and multi-dimensional understanding of texts, with a highlighted core.
            </p>
          </div>

          {/* Concept 5: Cauchy Sequence in C Shape */}
          <div className="bg-card border border-border/50 rounded-3xl p-10 flex flex-col items-center text-center group col-span-1 md:col-span-2">
            <div className="w-32 h-32 bg-background border border-border rounded-3xl flex items-center justify-center mb-8 transition-transform group-hover:scale-105">
              <svg width="64" height="64" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
                {/* Dots along a C-shape, spacing tightens */}
                <circle cx="78" cy="22" r="3.5" fill="currentColor" />
                <circle cx="47" cy="10" r="3.5" fill="currentColor" />
                <circle cx="22" cy="22" r="3.5" fill="currentColor" />
                <circle cx="11" cy="43" r="3.5" fill="currentColor" />
                <circle cx="12" cy="64" r="3.5" fill="currentColor" />
                <circle cx="22" cy="78" r="3.5" fill="currentColor" />
                <circle cx="33" cy="86" r="3.5" fill="currentColor" />
                <circle cx="44" cy="90" r="3.5" fill="currentColor" />
                
                {/* Converging dots in accent color */}
                <circle cx="53" cy="90" r="3.5" fill="var(--color-accent)" />
                <circle cx="60" cy="89" r="3.5" fill="var(--color-accent)" />
                <circle cx="66" cy="87" r="3.5" fill="var(--color-accent)" />
                <circle cx="71" cy="84" r="3.5" fill="var(--color-accent)" />
                <circle cx="74" cy="82" r="3.5" fill="var(--color-accent)" />
                <circle cx="76" cy="81" r="3.5" fill="var(--color-accent)" />
                <circle cx="77" cy="79" r="3.5" fill="var(--color-accent)" />
                <circle cx="78" cy="78" r="3.5" fill="var(--color-accent)" />
              </svg>
            </div>
            <h3 className="text-2xl font-medium mb-3">The Converging 'C'</h3>
            <p className="text-secondary text-[15px] leading-relaxed max-w-[80%] md:max-w-[50%]">
              A sequence of dots forming the letter 'C'. The dots maintain the same size, but the spacing between them tightens progressively as they approach the limit point, perfectly capturing the mathematical definition of a Cauchy sequence.
            </p>
          </div>

        </div>
      </div>
    </div>
  );
}
