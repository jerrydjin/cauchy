export const metadata = {
  title: "Privacy Policy | Cauchy",
  description: "Cauchy's privacy policy.",
};

export default function PrivacyPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Privacy Policy
      </h1>
      
      <div className="max-w-none text-[16px] leading-relaxed text-secondary [&>h2]:text-2xl [&>h2]:mt-12 [&>h2]:mb-4 [&>h2]:text-primary [&>h2]:font-medium [&>p]:mb-4">
        <p className="text-secondary text-lg mb-8">
          Last updated: July 18, 2026
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">Local-First Architecture</h2>
        <p className="text-secondary">
          Cauchy is built to run locally on your Mac. The application itself collects <strong>no telemetry</strong>, <strong>no analytics</strong>, and <strong>no usage tracking</strong>. We do not know when you open the app, what you read, or what questions you ask.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">Your Data</h2>
        <p className="text-secondary">
          All your workspaces, document state, and generated reference indexes are stored exclusively on your local disk at <code>~/Library/Application Support/Cauchy/</code>. We do not have servers to sync or store your data.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary">Third-Party AI Providers</h2>
        <p className="text-secondary">
          Cauchy acts as a bridge between your PDFs and your chosen AI provider. Depending on which provider you configure, some data must be sent off-device:
        </p>
        <ul className="list-disc pl-6 space-y-2 mt-4 text-secondary">
          <li><strong>Apple Intelligence:</strong> Models run entirely on-device. No data leaves your Mac.</li>
          <li><strong>Claude Code & Codex CLIs:</strong> Cauchy spawns your locally authenticated CLIs. The text you query and relevant context from your PDF will be sent to these providers subject to your existing agreements and their respective privacy policies.</li>
          <li><strong>Gemini API:</strong> If you provide a Gemini API key, the text of your queries and context from your documents will be sent to Google in accordance with the Google Cloud privacy policy.</li>
        </ul>

        <h2 className="text-2xl mt-12 mb-4 text-primary">Contact</h2>
        <p className="text-secondary">
          If you have questions about this policy, please open an issue on our GitHub repository.
        </p>
      </div>
    </div>
  );
}
