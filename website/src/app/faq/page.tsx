import Link from "next/link";

export const metadata = {
  title: "FAQ | Cauchy",
  description:
    "What Cauchy is, which assistants it supports, where your data lives, and why it ships unsandboxed.",
};

const REPO_URL = "https://github.com/jerrydjin/cauchy";

const inline =
  "text-primary underline underline-offset-4 decoration-secondary/40 hover:decoration-primary transition-colors";
const code = "bg-card border border-border px-1.5 py-0.5 rounded text-[14px]";

function Q({ q, children }: { q: string; children: React.ReactNode }) {
  return (
    <div>
      <h2 className="text-2xl font-medium tracking-tight text-primary mb-4">{q}</h2>
      <div className="text-[16px] leading-relaxed text-secondary space-y-4">{children}</div>
    </div>
  );
}

export default function FAQPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Frequently Asked Questions
      </h1>

      <p className="text-[18px] leading-relaxed text-secondary">
        Installation steps live in the{" "}
        <Link href="/setup" className={inline}>
          setup guide
        </Link>
        ; anything not answered here belongs in{" "}
        <a href={`${REPO_URL}/issues`} target="_blank" rel="noopener noreferrer" className={inline}>
          an issue
        </a>
        .
      </p>

      <div className="space-y-12 mt-12">
        <Q q="What is Cauchy?">
          <p>
            A native macOS app for reading PDFs that argue with you. Open a paper,
            highlight a line or drag a box around a figure, and ask about it; the answer
            appears in a thread pinned to that spot, with mathematics typeset properly. It
            is built for dense technical textbooks, mathematics papers and problem sets,
            not for contracts or slide decks.
          </p>
        </Q>

        <Q q="What can it actually do?">
          <ul className="list-disc pl-6 space-y-2">
            <li>
              Highlights that carry a conversation, saved with the document and named by
              the model after the first answer.
            </li>
            <li>
              Hover previews for cited results &mdash; theorems, lemmas, propositions,
              corollaries, definitions, examples and numbered equations get indexed, so
              &ldquo;by Theorem 2.1&rdquo; shows its statement without a page jump.
            </li>
            <li>
              Retrieval that reaches the rest of the document: BM25 keyword search plus
              on-device sentence embeddings supply passages from other pages.
            </li>
            <li>
              On-device OCR for equations the PDF stores as artwork, converted back to
              LaTeX before the question is sent.
            </li>
            <li>
              Reading essentials: continuous / single-page / two-up layouts, thumbnails,
              table of contents, contact sheet, ⌘F find, and a dashboard of recent
              documents.
            </li>
          </ul>
        </Q>

        <Q q="Which assistants can it use?">
          <p>
            Five connectors:{" "}
            <a href="https://www.apple.com/apple-intelligence/" target="_blank" rel="noopener noreferrer" className={inline}>
              Apple Intelligence
            </a>{" "}
            on-device,{" "}
            <a href="https://docs.claude.com/en/docs/claude-code/overview" target="_blank" rel="noopener noreferrer" className={inline}>
              Claude Code
            </a>
            ,{" "}
            <a href="https://github.com/openai/codex" target="_blank" rel="noopener noreferrer" className={inline}>
              Codex
            </a>{" "}
            and{" "}
            <a href="https://antigravity.google/" target="_blank" rel="noopener noreferrer" className={inline}>
              Antigravity
            </a>{" "}
            through their CLIs, and the{" "}
            <a href="https://aistudio.google.com/apikey" target="_blank" rel="noopener noreferrer" className={inline}>
              Gemini API
            </a>{" "}
            with your own key. The{" "}
            <Link href="/setup" className={inline}>
              setup guide
            </Link>{" "}
            covers each one.
          </p>
        </Q>

        <Q q="What does it cost?">
          <p>
            The app is free. Apple Intelligence costs nothing to run. The CLI connectors
            bill against the Anthropic, OpenAI or Google plan you already have, and the
            Gemini API bills your own key. Cauchy has no server, no account and no
            subscription of its own.
          </p>
        </Q>

        <Q q="Where is my data stored?">
          <p>
            Locally, and only locally. Workspaces &mdash; highlights, threads, viewport
            state and thumbnails &mdash; live in{" "}
            <code className={code}>~/Library/Application Support/Cauchy/workspaces/</code>,
            and cached reference indexes in{" "}
            <code className={code}>~/Library/Application Support/Cauchy/reference-index/</code>.
            A Gemini API key, if you add one, is kept in the macOS Keychain.
          </p>
        </Q>

        <Q q="Does Cauchy send my PDFs to the cloud?">
          <p>
            The file itself is never uploaded. With a cloud connector, what leaves your
            Mac is the question, the highlighted passage and the text around it, plus the
            statements and passages retrieval pulled from elsewhere in the document &mdash;
            subject to that provider&apos;s own terms. With Apple Intelligence, nothing
            leaves the machine.
          </p>
          <p>
            Cauchy itself collects no telemetry and no analytics. See the{" "}
            <Link href="/legal/privacy" className={inline}>
              privacy policy
            </Link>
            .
          </p>
        </Q>

        <Q q="Does it work offline?">
          <p>
            With the Apple Intelligence connector, yes &mdash; reading, highlighting, OCR,
            retrieval and reference indexing all run on-device. The CLI and Gemini
            connectors need a network.
          </p>
        </Q>

        <Q q="Why is the app unsandboxed?">
          <p>
            The Claude Code, Codex and Antigravity connectors work by spawning CLIs
            installed in your shell, which the macOS{" "}
            <a href={`${REPO_URL}#sandbox`} target="_blank" rel="noopener noreferrer" className={inline}>
              App Sandbox
            </a>{" "}
            forbids. Running unsandboxed means the app has the same access to your files as
            your user account does, and that it cannot be shipped through the Mac App
            Store.
          </p>
        </Q>

        <Q q="macOS says the app is damaged, or cannot be verified. Now what?">
          <p>
            &ldquo;Apple could not verify&hellip;&rdquo; is expected: releases are signed ad-hoc, not
            with a paid Developer ID. Open the app once from{" "}
            <strong className="text-primary">System Settings &gt; Privacy &amp; Security &gt; Open Anyway</strong>.
          </p>
          <p>
            &ldquo;Cauchy is damaged and can&apos;t be opened&rdquo; means you have a v1.0.0&ndash;v1.0.2
            build, which shipped half-signed and is blocked outright. Get{" "}
            <a href={`${REPO_URL}/releases`} target="_blank" rel="noopener noreferrer" className={inline}>
              a newer release
            </a>{" "}
            or run{" "}
            <code className={code}>xattr -dr com.apple.quarantine /Applications/Cauchy.app</code>.
          </p>
        </Q>

        <Q q="Which macOS versions are supported?">
          <p>
            macOS 27.0 (Golden Gate) and later. Earlier versions are not supported: the app
            is built against the macOS 27 SDK and uses frameworks that do not exist before
            it.
          </p>
        </Q>

        <Q q="Is it open source? Can I build it myself?">
          <p>
            The source is public at{" "}
            <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className={inline}>
              github.com/jerrydjin/cauchy
            </a>
            . Building needs Xcode 27 beta or later with the macOS 27 SDK; the{" "}
            <a href={`${REPO_URL}#open-in-xcode`} target="_blank" rel="noopener noreferrer" className={inline}>
              README
            </a>{" "}
            has the steps, including the local{" "}
            <a href="https://github.com/mgriebling/SwiftMath" target="_blank" rel="noopener noreferrer" className={inline}>
              SwiftMath
            </a>{" "}
            checkout that renders the mathematics.
          </p>
        </Q>

        <Q q="Is there a Homebrew cask, or an iPad version?">
          <p>
            Neither, for now. Installation is the{" "}
            <a href={`${REPO_URL}/releases/latest`} target="_blank" rel="noopener noreferrer" className={inline}>
              .dmg from the latest release
            </a>
            , and Cauchy is macOS-only.
          </p>
        </Q>
      </div>
    </div>
  );
}
