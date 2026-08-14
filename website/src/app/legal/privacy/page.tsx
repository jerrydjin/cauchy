import Link from "next/link";

export const metadata = {
  title: "Privacy Policy | Cauchy",
  description:
    "Cauchy collects no telemetry. What stays on your Mac, and what a cloud connector sends when you ask a question.",
};

const REPO_URL = "https://github.com/jerrydjin/cauchy";

const inline =
  "text-primary underline underline-offset-4 decoration-secondary/40 hover:decoration-primary transition-colors";

export default function PrivacyPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Privacy Policy
      </h1>

      <div className="max-w-none text-[16px] leading-relaxed text-secondary [&>p]:mb-4">
        <p className="text-secondary text-lg mb-8">
          Last updated: August 15, 2026
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Local-First Architecture</h2>
        <p>
          Cauchy runs on your Mac and talks to no server of ours, because there is none.
          The app collects <strong className="text-primary">no telemetry</strong>,{" "}
          <strong className="text-primary">no analytics</strong> and{" "}
          <strong className="text-primary">no crash reports</strong>. We do not know when
          you open it, what you read, or what you ask.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Your Data</h2>
        <p>
          Workspaces &mdash; highlights, threads, viewport state and thumbnails &mdash; are
          written to{" "}
          <code>~/Library/Application Support/Cauchy/workspaces/</code>, and cached
          reference indexes to <code>~/Library/Application Support/Cauchy/reference-index/</code>.
          A Gemini API key, if you add one, lives in the macOS Keychain. Deleting those
          folders deletes the data; nothing is synced anywhere.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">
          What Leaves Your Mac When You Ask
        </h2>
        <p>
          The PDF itself is never uploaded. With a cloud connector, a question sends the
          text you highlighted, the text around it, and the statements and passages
          retrieval selected from elsewhere in the same document. Which provider receives
          it depends on the connector you chose:
        </p>
        <ul className="list-disc pl-6 space-y-2 mt-4">
          <li>
            <strong className="text-primary">Apple Intelligence:</strong> runs on-device.
            Nothing leaves your Mac.
          </li>
          <li>
            <strong className="text-primary">Claude Code (Anthropic):</strong> Cauchy spawns
            the <code>claude</code> CLI you signed into; the request goes to Anthropic under
            your existing agreement and their{" "}
            <a href="https://www.anthropic.com/legal/privacy" target="_blank" rel="noopener noreferrer" className={inline}>
              privacy policy
            </a>
            .
          </li>
          <li>
            <strong className="text-primary">Codex (OpenAI):</strong> the same, through the{" "}
            <code>codex</code> CLI, under OpenAI&apos;s{" "}
            <a href="https://openai.com/policies/privacy-policy/" target="_blank" rel="noopener noreferrer" className={inline}>
              privacy policy
            </a>
            .
          </li>
          <li>
            <strong className="text-primary">Antigravity (Google):</strong> through the{" "}
            <code>agy</code> CLI and your Google sign-in, under Google&apos;s{" "}
            <a href="https://policies.google.com/privacy" target="_blank" rel="noopener noreferrer" className={inline}>
              privacy policy
            </a>
            .
          </li>
          <li>
            <strong className="text-primary">Gemini API (Google):</strong> sent directly to
            the Gemini API with your key, under the{" "}
            <a href="https://ai.google.dev/gemini-api/terms" target="_blank" rel="noopener noreferrer" className={inline}>
              Gemini API terms
            </a>
            .
          </li>
        </ul>
        <p className="mt-4">
          Cauchy holds no credentials for these services. CLI connectors use the sign-in
          already on your machine; the Gemini key is yours and is read from the Keychain
          only to make the call.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Reference Indexing</h2>
        <p>
          Building the theorem and definition index reads pages of your document through a
          model. It prefers the on-device Apple Intelligence model, and falls back to
          Gemini only when you have supplied a key and the on-device model is unavailable.
          Results are cached locally and never leave your Mac.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">This Website</h2>
        <p>
          The site is a static Next.js build hosted on Vercel and sets no analytics or
          advertising cookies. Downloads are served by GitHub Releases, which applies{" "}
          <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement" target="_blank" rel="noopener noreferrer" className={inline}>
            GitHub&apos;s privacy statement
          </a>
          .
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Contact</h2>
        <p>
          Questions about this policy belong in{" "}
          <a href={`${REPO_URL}/issues`} target="_blank" rel="noopener noreferrer" className={inline}>
            a GitHub issue
          </a>
          . See also the{" "}
          <Link href="/legal/terms" className={inline}>
            terms of use
          </Link>
          .
        </p>
      </div>
    </div>
  );
}
