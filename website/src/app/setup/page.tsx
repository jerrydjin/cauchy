import Link from "next/link";

export const metadata = {
  title: "Setup | Cauchy",
  description:
    "Install Cauchy on macOS and connect an assistant: Apple Intelligence, Claude Code, Codex, Antigravity, or a Gemini API key.",
};

const REPO_URL = "https://github.com/jerrydjin/cauchy";
const DOWNLOAD_URL =
  "https://github.com/jerrydjin/cauchy/releases/latest/download/Cauchy.dmg";

const inline =
  "text-primary underline underline-offset-4 decoration-secondary/40 hover:decoration-primary transition-colors";
const code = "bg-card border border-border px-1.5 py-0.5 rounded text-[14px] text-primary";

function Block({ children }: { children: React.ReactNode }) {
  return (
    <div className="bg-card border border-border rounded-md p-4 my-6">
      <code className="text-[14px] text-primary">{children}</code>
    </div>
  );
}

export default function SetupPage() {
  return (
    <div className="w-full max-w-3xl mx-auto px-6 py-24 sm:py-32">
      <h1 className="text-[40px] sm:text-[56px] font-medium tracking-[-0.03em] leading-[1.1] text-primary mb-8">
        Setup
      </h1>

      <p className="text-[18px] leading-relaxed text-secondary">
        Cauchy is a native macOS app. Installing it takes one download; picking where
        answers come from takes one more step, and one of the five options needs nothing
        at all.
      </p>

      <div className="max-w-none text-[16px] leading-relaxed text-secondary">
        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Requirements</h2>
        <ul className="list-disc pl-6 space-y-2">
          <li>macOS 27.0 (Golden Gate) or later.</li>
          <li>
            An Apple Silicon Mac if you want the on-device Apple Intelligence connector.
          </li>
          <li>
            Nothing else. There is no account to create and no license key.
          </li>
        </ul>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Install</h2>
        <p>
          Download{" "}
          <a href={DOWNLOAD_URL} className={inline}>
            Cauchy.dmg
          </a>{" "}
          from the{" "}
          <a href={`${REPO_URL}/releases/latest`} target="_blank" rel="noopener noreferrer" className={inline}>
            latest release
          </a>
          , open it, and drag <strong className="text-primary">Cauchy.app</strong>{" "}
          into Applications. There is no Homebrew cask yet, and Cauchy is not on the Mac App
          Store &mdash; see{" "}
          <Link href="/faq" className={inline}>
            the FAQ
          </Link>{" "}
          for why.
        </p>
        <p className="mt-4">
          Releases are signed ad-hoc rather than with a paid Developer ID, so the first
          launch shows &ldquo;Apple could not verify Cauchy is free of malware&rdquo;. Open it once
          from <strong className="text-primary">System Settings &gt; Privacy &amp; Security &gt; Open Anyway</strong>,
          and macOS stops asking.
        </p>
        <p className="mt-4">
          If instead you see <em>&ldquo;Cauchy is damaged and can&apos;t be opened&rdquo;</em>, you are on
          one of the v1.0.0&ndash;v1.0.2 builds, which shipped half-signed. Download{" "}
          <a href={`${REPO_URL}/releases`} target="_blank" rel="noopener noreferrer" className={inline}>
            v1.0.3 or later
          </a>
          , or clear the quarantine flag by hand:
        </p>
        <Block>xattr -dr com.apple.quarantine /Applications/Cauchy.app</Block>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Build from source</h2>
        <p>
          Building needs Xcode 27 beta or later with the macOS 27 SDK &mdash; Command Line
          Tools alone cannot build the app. The full instructions, including the SwiftMath
          checkout and the project generator, are in the{" "}
          <a href={`${REPO_URL}#open-in-xcode`} target="_blank" rel="noopener noreferrer" className={inline}>
            README
          </a>
          .
        </p>
        <Block>git clone https://github.com/jerrydjin/cauchy.git &amp;&amp; cd cauchy &amp;&amp; ./scripts/run.sh</Block>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">
          Choose an assistant
        </h2>
        <p>
          The connector picker sits next to the ask field, and Settings remembers your
          choice. Every option bills to you, not to Cauchy: an on-device model costs
          nothing, a CLI rides the subscription you already pay for, and the Gemini API
          uses your own key.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary font-medium">
          Apple Intelligence &mdash; nothing to set up
        </h3>
        <p>
          Turn on{" "}
          <a href="https://www.apple.com/apple-intelligence/" target="_blank" rel="noopener noreferrer" className={inline}>
            Apple Intelligence
          </a>{" "}
          in System Settings and Cauchy can use the system model through Apple&apos;s{" "}
          <a href="https://developer.apple.com/documentation/foundationmodels" target="_blank" rel="noopener noreferrer" className={inline}>
            Foundation Models
          </a>{" "}
          framework. There is one model, so no model picker appears. Reference indexing
          prefers this connector even when you ask questions with another one.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary font-medium">
          Claude Code &mdash; your Anthropic subscription
        </h3>
        <p>
          Install{" "}
          <a href="https://docs.claude.com/en/docs/claude-code/overview" target="_blank" rel="noopener noreferrer" className={inline}>
            Claude Code
          </a>
          , then run <code className={code}>claude</code> in Terminal and log in. Cauchy
          detects the <code className={code}>claude</code> binary, spawns it per ask, and
          never sees your credentials. Models offered: Fable, Opus, Sonnet and Haiku.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary font-medium">
          Codex &mdash; your ChatGPT plan
        </h3>
        <p>
          Install OpenAI&apos;s{" "}
          <a href="https://github.com/openai/codex" target="_blank" rel="noopener noreferrer" className={inline}>
            Codex CLI
          </a>{" "}
          and sign in once:
        </p>
        <Block>brew install codex &amp;&amp; codex login</Block>
        <p>
          The picker then offers the GPT-5.6 Sol, Terra and Luna tiers.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary font-medium">
          Antigravity &mdash; your Google sign-in
        </h3>
        <p>
          Install{" "}
          <a href="https://antigravity.google/" target="_blank" rel="noopener noreferrer" className={inline}>
            Antigravity
          </a>
          &apos;s CLI, then run <code className={code}>agy</code> and sign in with Google:
        </p>
        <Block>curl -fsSL https://antigravity.google/cli/install.sh | bash</Block>
        <p>
          <code className={code}>agy</code> takes no model argument, so Cauchy shows no
          model picker for it &mdash; set the model with <code className={code}>/model</code>{" "}
          inside agy and Cauchy follows it.
        </p>

        <h3 className="text-xl mt-8 mb-4 text-primary font-medium">
          Gemini API &mdash; bring your own key
        </h3>
        <p>
          Create a key in{" "}
          <a href="https://aistudio.google.com/apikey" target="_blank" rel="noopener noreferrer" className={inline}>
            Google AI Studio
          </a>{" "}
          and paste it into Cauchy&apos;s Settings. It is stored in the macOS Keychain, never
          in a plist, and usage is billed to your Google account. Gemini is also the
          fallback that builds reference indexes on Macs without Apple Intelligence.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">
          Why the app is unsandboxed
        </h2>
        <p>
          Three of the five connectors work by spawning a CLI that lives in your shell.
          The macOS{" "}
          <a href={`${REPO_URL}#sandbox`} target="_blank" rel="noopener noreferrer" className={inline}>
            App Sandbox
          </a>{" "}
          forbids that outright, so Cauchy ships unsandboxed and has the same access to
          your files as you do. That is also why it cannot be distributed through the Mac
          App Store.
        </p>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Where files land</h2>
        <ul className="list-disc pl-6 space-y-2">
          <li>
            <code className={code}>~/Library/Application Support/Cauchy/workspaces/&lt;id&gt;/</code>{" "}
            &mdash; highlights, threads, viewport state, thumbnails.
          </li>
          <li>
            <code className={code}>~/Library/Application Support/Cauchy/reference-index/</code>{" "}
            &mdash; cached theorem and definition indexes, rebuilt on demand.
          </li>
          <li>
            Sidecar files written beside the PDF by older versions are migrated on open.
          </li>
        </ul>

        <h2 className="text-2xl mt-12 mb-4 text-primary font-medium">Still stuck?</h2>
        <p>
          Open an issue at{" "}
          <a href={`${REPO_URL}/issues`} target="_blank" rel="noopener noreferrer" className={inline}>
            github.com/jerrydjin/cauchy/issues
          </a>
          , or read the rest of the{" "}
          <Link href="/faq" className={inline}>
            FAQ
          </Link>
          .
        </p>
      </div>
    </div>
  );
}
