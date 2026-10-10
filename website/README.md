# Cauchy website

The Next.js site for the native macOS Cauchy PDF reader. Product, setup, FAQ and
privacy content should describe the app in this repository.

## Develop and verify

```bash
npm ci
npm run dev
```

Open `http://localhost:3000`. Routes live in `src/app/` and shared components in
`src/components/`.

```bash
npm run build
npm run lint
```

Google fonts are fetched at build time. In a proxy-based environment where
Turbopack cannot fetch them, `npm run build -- --webpack` uses Next.js's Node
font fetcher and its configured proxy.

## Keep content aligned with the app

- `src/lib/assistants.ts` supplies the homepage, setup guide, FAQ and footer.
  Compare it with `Cauchy/Models/AssistantConnector.swift` and
  `Cauchy/Models/CloudAPIProvider.swift` when adding a connector or changing its
  model choices. The connector count is derived from the shared catalog.
- Verify setup steps and Automatic selection against `SettingsView.swift`,
  `ConnectorSetupView.swift` and `AssistantPreferences.swift`.
- Check reading and export instructions against `Cauchy/App/ReaderCommands.swift`
  and `Cauchy/ViewModels/WorkspaceViewModel+Export.swift`.
- Keep evidence and privacy wording aligned with `SelectionThread.swift`,
  `ReadingPromptBuilder.swift` and `LLMReferenceIndexBuilder.swift`. Cloud API
  reference indexing can send rendered page images as well as text. Evidence
  labels and source links do not prove an answer's claims.
- Update `/`, `/setup`, `/faq`, `/legal/privacy`, `/legal/terms` and the metadata
  in `src/app/layout.tsx` together when app behavior changes.
- Download links use GitHub's `releases/latest/download/Cauchy.dmg` URL so they
  follow the latest published release without a pinned version.

The hero uses the native, shadow-free app capture in
`public/app-screenshot.png` (3300 × 2168), showing a highlighted Cayley–Hamilton
theorem, the answer's evidence boundary and expanded PDF source links. When
replacing it, update its dimensions and alt text in both the homepage and social
metadata.
