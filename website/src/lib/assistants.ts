// Keep this catalog aligned with Cauchy/Models/AssistantConnector.swift.
// Product pages and navigation share it so connector lists stay consistent.
export const assistants = [
  {
    id: "onDevice",
    name: "Apple Intelligence",
    url: "https://www.apple.com/apple-intelligence/",
    description:
      "The system model runs entirely on your Mac. Enable Apple Intelligence in System Settings; no key or network is needed. Reference indexing uses it by default when available.",
  },
  {
    id: "claudeCode",
    name: "Claude Code",
    url: "https://docs.claude.com/en/docs/claude-code/overview",
    description:
      "Connect your Claude account in Cauchy’s Settings. The guided flow installs the CLI, handles provider sign-in, and checks the connection. Choose Fable, Opus, Sonnet or Haiku for answers.",
  },
  {
    id: "codex",
    name: "Codex",
    url: "https://github.com/openai/codex",
    description:
      "Connect your ChatGPT account in Settings using the guided CLI installation and sign-in. The model picker offers GPT-6.1 Sol, GPT-6.1 Terra, GPT-6 Astra, and GPT-6 Luna.",
  },
  {
    id: "antigravity",
    name: "Antigravity",
    url: "https://antigravity.google/",
    description:
      "Connect your Google account in Settings. The model picker offers Gemini 4 Argon and Gemini 3.8 Flash, with the reasoning effort in each row.",
  },
  {
    id: "anthropicAPI",
    name: "Anthropic API",
    url: "https://platform.claude.com/settings/keys",
    description:
      "Add your own Anthropic key under Settings → Your API keys. Choose Fable, Opus, Sonnet or Haiku. The key lives in your macOS Keychain and API usage is billed separately by Anthropic.",
  },
  {
    id: "openaiAPI",
    name: "OpenAI API",
    url: "https://platform.openai.com/api-keys",
    description:
      "Add your own OpenAI key under Settings → Your API keys. Choose GPT-6.1 Sol, GPT-6.1 Terra, GPT-6 Astra, or GPT-6 Luna. The key lives in your macOS Keychain and API usage is billed separately from your ChatGPT plan.",
  },
  {
    id: "gemini",
    name: "Gemini API",
    url: "https://aistudio.google.com/apikey",
    description:
      "Create a key in Google AI Studio and add it under Settings → Your API keys. Argon, Flash, and Flash-Lite models are available. The key lives in your macOS Keychain and usage is billed to your Google account.",
  },
] as const;
