# Compass - Local AI

A privacy-first, on-device assistant. Ask questions, attach images, and get helpful answers generated **on your device by default**. Compass can *optionally* perform grounded web search with inline citations when you turn it on — and it always keeps working fully offline.

## Features

- On-device chat powered by Apple Intelligence (Foundation Models) when available, with a lightweight on-device fallback otherwise
- Image understanding using on-device OCR (Vision)
- **Long-session memory:** retains facts from early in a conversation via a rolling on-device summary plus semantic recall, so context isn't lost after a handful of turns
- **Optional** web search with Perplexity-style citations (off by default; disclosed and user-controlled)
- **Offline-first:** web search is automatically skipped with no network, and answers stay 100% on-device
- Clean, professional Apple-style UI

## How answers are produced (multi-agent orchestration)

Compass uses a small on-device agent pipeline inspired by ReAct, Plan-and-Solve decomposition, RAG, and Reflexion-style verification — mapped onto a Perplexity-style retrieval flow:

1. **QueryPlanner** — classifies intent and decides whether an answer needs fresh/external facts; decomposes the request into focused sub-queries. Deterministic by default; refined by Apple Intelligence when available.
2. **RetrievalAgent** — (only when web search is enabled AND online) fans sub-queries out to the search provider, dedupes, and reranks candidates **on-device** with a hybrid BM25 + `NLEmbedding` scorer, applying a ~0.7 quality gate with a re-query fail-safe.
3. **SynthesisAgent** — synthesizes the answer constrained to the retrieved evidence and attaches inline `[N]` citations. Offline / no-AI it falls back to on-device generation or extractive synthesis.
4. **VerifierAgent** — drops unsupported citations and renumbers the ones actually used, so references stay consistent.
5. **Orchestrator** — coordinates the agents and enforces the offline-first and privacy rules.

### Search providers

- **DuckDuckGo** — keyless default, works out of the box.
- **Brave Search** — optional; add an API key in Settings for broader, higher-quality cited results.

The search backend is pluggable (`SearchProvider` protocol), so additional providers can be added easily.

## Conversation memory (long sessions)

On-device models have a small context window, so Compass can't just paste an entire transcript back to the model. Instead, `ConversationMemory` combines three research-backed techniques so long sessions stay coherent and earlier facts aren't forgotten:

1. **Recent buffer** — the last several turns are always kept verbatim, since recency dominates conversational coherence.
2. **Rolling summary memory** — messages older than the buffer are folded into a compact summary (a *summary buffer memory*) using Apple Intelligence when available, with a deterministic heuristic fallback otherwise. The summary is **persisted with the conversation** (`Conversation.summary` + `memoryWatermark`), so memory survives app restarts.
3. **Semantic recall** — the specific older messages most relevant to the current question are retrieved on-device via `NLEmbedding` cosine similarity and re-injected verbatim, so precise details (a name, a date) aren't lost to summarization.

The assembled context is capped to a fixed character budget so it never overflows the model window. All of this runs fully on-device; nothing about your conversation is sent anywhere.

## What happens on your device

- **Chat:** Your text questions are processed on-device by default.
- **OCR (images):** If you attach an image, its text is extracted using Apple’s on-device OCR. No image/OCR text is sent to external services.
- **Storage:** Conversations — including the on-device memory summary of each session — are saved locally in the app. We have no access.
- **No analytics or tracking:** Compass - Local AI does not use analytics, advertising, or tracking.
- **Web search (optional, off by default):** If — and only if — you turn on web search in Settings *and* you are online, your search query is sent to the search provider you selected (DuckDuckGo or Brave) so answers can be grounded and cited. Turn it off (or go offline) and nothing leaves your device.

## Privacy Policy

**We do not collect your data.** Compass - Local AI does **not** collect, store, or transmit any of your personal data to our servers, and we operate no backend that can access your conversations.

### What happens on your device

- **Chat:** Your questions and the assistant’s answers are processed on your device. We do not send your chat content to any server we operate.
- **Images & OCR:** When you attach an image, Compass - Local AI uses Apple’s on-device Vision/OCR APIs to read text from the image. The image and extracted text stay on your device and are not uploaded to anyone.
- **Conversations & memory:** Your conversations, and the rolling memory summary Compass builds to remember context across a long session, are stored only in the app’s local storage on your device.
- **No analytics or tracking:** Compass - Local AI does not use analytics, advertising, or tracking SDKs. We do not collect device identifiers, usage statistics, or any other telemetry.

### Optional web search

Web search is **off by default**. When you explicitly enable it in Settings and your device is online, the assistant sends your search query (a reformulated version of your question) to the third-party search provider you selected — DuckDuckGo, or Brave if you supply an API key — in order to retrieve sources and cite them. Those providers have their own privacy policies. Compass sends only the query text; it does not attach identifiers or your conversation history. When web search is off, or when you are offline, no query or content leaves your device.

### Permissions we use

- **Photo Library:** Used only when you choose to attach an image. Access is limited to the photos you select; we do not collect or upload them.

### Changes to this policy

If we change this policy (for example, to describe new features), we will update this page and the “Last updated” date in the app’s Privacy Policy screen.

### Contact

If you have questions about privacy or this policy, contact us using the support email listed on the Compass - Local AI App Store page.

## Requirements

- iOS 26+ (deployment target). Apple Intelligence–capable devices get the on-device Foundation Models reasoner; other devices use the lightweight on-device fallback.
- Xcode 16+ (iOS 26 SDK + Foundation Models). Verified building with Xcode 26.

## Setup

1. Open `Compass.xcodeproj` in Xcode (app name: Compass - Local AI). The project is also generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen); run `xcodegen generate` after adding files if you use it.
2. Select your development team under Signing & Capabilities.
3. Build and run on a device (recommended).
4. (Optional) In-app **Settings** → turn on **Web search** for cited answers. Leave it off to stay fully on-device. Add a Brave Search API key for higher-quality results.

## Contact

If you have questions about privacy, use the support email you list in your App Store listing.

