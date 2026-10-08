# Notes Sidecar Launch Kit (English)

Updated: 2026-10-07  
Positioning: A private AI conversation companion that works beside Apple Notes on macOS.

> Product boundary: This copy describes features implemented in the current build. Model responses and availability depend on the provider configured by the user; do not claim model accuracy, real-time knowledge, or third-party service availability.

## One-line description

Talk to AI beside the Apple Note you are reading — without copying the note into a chat window.

## Who it is for

- Mac users who organize projects, research, meeting notes, or personal material in Apple Notes.
- People who want to choose their own AI provider and keep API keys on their Mac.
- Anyone who wants every note to retain a separate, unambiguous AI conversation.

## Key benefits

1. **One conversation per note**  
   Read the selected Apple Note and automatically switch to that note’s matching conversation when the selection changes.

2. **Ask directly; do not paste the note**  
   The selected note supplies context while the composer contains only the user’s question. Quick actions can summarize, extract tasks, restructure a note, or find gaps immediately.

3. **Local privacy filtering before sending**  
   Text and images are inspected locally before a request is created. When credentials, tokens, secrets, or other sensitive context are detected, the relevant portion is excluded and Sidecar explains why. Original images are not uploaded for recognition.

4. **Bring your own provider**  
   Use Anthropic, OpenAI, DeepSeek, Moonshot, Zhipu GLM, MiniMax, Ollama, or an OpenAI-compatible service. Requests go directly from this Mac to the provider chosen by the user; there is no developer relay server.

5. **Local-first credentials and history**  
   API keys are stored in macOS Keychain. Conversations and drafts are stored per note. Ollama supports local model workflows.

6. **Review before writing back**  
   Preview an answer before inserting it into the current note or creating a new one. Conflict protection helps prevent accidental overwrites.

7. **Designed for desktop work**  
   Pin the window, minimize it, work docked beside Notes or independently, and choose light, dark, or technology themes. The interface uses Simplified Chinese only on Simplified Chinese systems; otherwise it uses English.

## App Store metadata draft

### App name

`Notes Sidecar`

Check availability in App Store Connect before finalizing. Alternatives: `Notes Sidecar AI` or `Sidecar for Notes`.

### Subtitle options

- AI conversations beside your notes
- Private AI workspace for Apple Notes

### Promotional text (under 170 characters)

Ask AI about the Apple Note you are reading. Keep a separate conversation for every note, choose your own provider, and filter sensitive context locally before sending.

### Long description

Notes Sidecar brings an AI conversation to the edge of Apple Notes. Open the Sidecar, select a note, and ask a question — the note stays the context while your message stays your message. There is no need to copy a whole note into a prompt field.

Every note has its own conversation. When you move to another note, Sidecar follows with the matching chat, so a meeting summary never mixes with research or a personal checklist. Use built-in quick actions to summarize, extract tasks, restructure a note, or identify missing information.

Privacy is built into the sending path. Text and images are inspected locally before a request is created. When sensitive content is found, that portion is excluded and Sidecar tells you why. Original images are not uploaded for recognition.

Bring your own provider: Anthropic, OpenAI, DeepSeek, Moonshot, Zhipu GLM, MiniMax, Ollama, and OpenAI-compatible services. Requests go directly from your Mac to the provider you configure. API keys stay in the macOS Keychain.

When a result belongs in your notes, preview it before writing it back. Choose whether to insert it into the current note or create a new note, with conflict protection for safer edits.

Notes Sidecar supports light, dark, and technology themes; it uses Simplified Chinese when macOS does, and English otherwise.

### Keyword candidates

`notes, ai, assistant, apple notes, productivity, summarize, writing, research, privacy, ollama`

Trim this list to App Store Connect’s character limit and validate current search terms before submission. Do not stuff third-party trademarks into keywords.

## App Store screenshot plan — English

Create these screenshots only with demo notes that contain no personal data, API keys, tokens, copyrighted third-party material, or identifiable account information. The screen must run with English selected; no Chinese UI may appear.

| # | File | Scene | Overlay headline |
| --- | --- | --- | --- |
| 1 | `截图/en-US/01-current-note-chat.png` | Notes and Sidecar side by side, showing a project note and its chat | `Ask AI in the context of your note` |
| 2 | `截图/en-US/02-note-switching.png` | Changing the selected note switches Sidecar to a separate conversation | `One conversation for every note` |
| 3 | `截图/en-US/03-privacy-filter.png` | Safe demo note and a pre-send privacy notice with sensitive text masked | `Sensitive context stays out of requests` |
| 4 | `截图/en-US/04-quick-actions.png` | The four quick actions: summarize, extract tasks, restructure, and find gaps | `Turn notes into next steps` |
| 5 | `截图/en-US/05-provider-choice.png` | Dark provider selection and Ollama configuration | `Choose the AI provider you trust` |
| 6 | `截图/en-US/06-write-back-preview.png` | Write-back preview with conflict protection | `Review before writing back` |
| 7 | `截图/en-US/07-window-themes.png` | Light, dark, and technology-theme triptych | `Fits your desktop workflow` |

## App Review Notes draft

Notes Sidecar is a local macOS companion for Apple Notes. It accesses the currently selected note only after the user enables the relevant macOS Automation permission. Accessibility is optional and is used only when the user enables window following.

The app has no developer relay server. When a user submits a question, selected note context is sent directly from that Mac to the AI provider configured by the user. API keys are stored locally in macOS Keychain. Before sending, the app performs local privacy filtering; sensitive portions are excluded from the request. Original images are not uploaded for local recognition.

To test the core UI without a provider: open Settings → Notes Connection and use Test Read after granting Automation permission. Provider configuration is under Settings → Model Providers. A configured provider key is required only to obtain model-generated replies.

Before submission, verify that this statement matches the shipping build’s sandbox entitlements verbatim. If the Notes Apple Events temporary exception remains necessary, add its least-privilege rationale and the relevant Feedback reference number.

## 30-second product demo script

1. Open a demo project note in Apple Notes; Sidecar shows the note title and existing conversation.
2. Ask “Extract owners and due dates,” then show the streamed task result.
3. Select another note and show Sidecar switching to its independent conversation.
4. Open the privacy-notice demo and show that sensitive context is excluded before sending.
5. Open Provider settings and show a cloud provider option plus local Ollama; explain that API keys are stored in macOS Keychain.
6. Choose “Insert into Note” and show the write-back preview rather than overwriting the note.

## Pre-release checklist

- [ ] Seven final screenshots are exported in the macOS sizes actually supported by App Store Connect.
- [ ] Every English screenshot is captured with English UI; no Chinese text appears.
- [ ] No screenshot includes names, contact details, addresses, account identifiers, tokens, API keys, real note contents, or unlicensed brand material.
- [ ] App name, subtitle, description, keywords, support URL, and privacy-policy URL have final owner approval.
- [ ] App Review Notes match the shipping sandbox entitlements.
- [ ] A clean macOS account has completed the install, permissions, provider setup, conversation, and write-back recording.

## Related material

- [Simplified Chinese launch kit](Notes%20Sidecar%20上线介绍资料.md)
- [App Store low-cost launch plan](../App%20Store低成本上线计划.md)
- [Apple developer capabilities checklist](../Apple开发者权限与开通清单.md)
