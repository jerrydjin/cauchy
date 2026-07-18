export const metadata = {
  title: "Setup | Cauchy",
  description: "How to set up Cauchy and connect your AI assistants.",
};

export default function SetupPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Setup
      </h1>
      
      <div className="max-w-none text-[16px] leading-relaxed text-secondary [&>h2]:text-2xl [&>h2]:mt-12 [&>h2]:mb-4 [&>h2]:text-primary [&>h2]:font-medium [&>h3]:text-xl [&>h3]:mt-8 [&>h3]:mb-4 [&>h3]:text-primary [&>h3]:font-medium [&>p]:mb-4 [&>a]:text-accent hover:[&>a]:text-accent-hover">
        <h2 className="text-2xl mt-12 mb-4 text-primary">Basic Installation</h2>
        <p className="text-secondary">
          You can download the pre-built macOS application or install it via Homebrew:
        </p>
        <div className="bg-card border border-border rounded-md p-4 my-6">
          <code className="text-[14px] text-primary">brew install --cask cauchy</code>
        </div>
        
        <h2 className="text-2xl mt-12 mb-4 text-primary">Assistant Configuration</h2>
        <p className="text-secondary">
          Cauchy is built to work with the tools you already have installed on your Mac. You can choose which provider to use for answering questions about your documents.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary">Claude Code & Codex CLIs</h3>
        <p className="text-secondary">
          If you have the Claude Code or Codex CLI tools installed and authenticated on your machine, Cauchy can use them directly. Cauchy will automatically detect your local installation and use it to power the assistant features.
        </p>
        <p className="text-secondary mt-4">
          <strong>Note on Sandboxing:</strong> Cauchy is distributed as an <em>unsandboxed</em> application. Apple&apos;s App Sandbox prevents applications from spawning arbitrary terminal commands or interacting with your shell environment. By running unsandboxed, Cauchy can securely spawn your locally installed CLIs and utilize your existing authentications.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary">Gemini API</h3>
        <p className="text-secondary">
          You can also provide a Gemini API key. Just open Cauchy&apos;s settings and paste your key. This will use the Gemini API directly for processing your document queries.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary">Apple Intelligence</h3>
        <p className="text-secondary">
          For macOS 27.0 (Golden Gate) or later, Cauchy supports on-device Apple Intelligence models. This requires a compatible Apple Silicon Mac and will process everything entirely on your device.
        </p>
      </div>
    </div>
  );
}
