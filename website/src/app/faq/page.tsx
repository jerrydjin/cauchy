export const metadata = {
  title: "FAQ | Cauchy",
  description: "Frequently asked questions about Cauchy.",
};

export default function FAQPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Frequently Asked Questions
      </h1>
      
      <div className="space-y-12 mt-12">
        <div>
          <h2 className="text-2xl font-medium tracking-tight text-primary mb-4">
            What is Cauchy?
          </h2>
          <p className="text-[16px] leading-relaxed text-secondary">
            It is a macOS app to open PDF documents, highlight things you want to understand better, and talk to an AI assistant about them. It is designed for dense technical textbooks, mathematics papers, and academic problem sets.
          </p>
        </div>

        <div>
          <h2 className="text-2xl font-medium tracking-tight text-primary mb-4">
            Where is my data stored?
          </h2>
          <p className="text-[16px] leading-relaxed text-secondary">
            100% locally on your machine. Your workspaces, highlights, and document states are stored in <code className="bg-card border border-border px-1.5 py-0.5 rounded text-[14px]">~/Library/Application Support/Cauchy/workspaces/</code>. 
          </p>
        </div>

        <div>
          <h2 className="text-2xl font-medium tracking-tight text-primary mb-4">
            Why is the app unsandboxed?
          </h2>
          <p className="text-[16px] leading-relaxed text-secondary">
            macOS App Sandbox forbids spawning arbitrary terminal tools. Cauchy needs to run unsandboxed to utilize your locally installed Claude Code or Codex CLIs. Because of this, it cannot be distributed through the Mac App Store and requires you to download it directly.
          </p>
        </div>

        <div>
          <h2 className="text-2xl font-medium tracking-tight text-primary mb-4">
            Does Cauchy send my PDFs to the cloud?
          </h2>
          <p className="text-[16px] leading-relaxed text-secondary">
            Cauchy itself does not upload your documents anywhere. If you choose to use the Gemini API or the Claude/Codex CLIs, the text you highlight and ask about will be sent to those providers according to their respective privacy policies. If you use the Apple Intelligence provider, everything stays completely on-device.
          </p>
        </div>
      </div>
    </div>
  );
}
