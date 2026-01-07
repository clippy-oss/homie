# Agent Rules

1. **Keep diffs minimal** - targeted edits only
2. **Follow existing patterns** - match the codebase style
3. **Type safety** - avoid `any` unless necessary
4. **Search narrowly** - avoid reading large files/assets

---

## Monorepo Structure

```
homie_project/
├── homie/                    # macOS desktop app (Swift/SwiftUI)
│   └── homie/
│       ├── Auth/             # Authentication & permissions
│       ├── LLM/              # Language model integration
│       ├── MCP/              # Model Context Protocol servers
│       ├── VoicePipeline/    # Audio processing pipeline
│       ├── SpeechProcessing/ # Whisper STT integration
│       ├── Settings/         # User preferences UI
│       └── FeatureGateway/   # Feature flags & entitlements
├── homie_website/            # Web app (Next.js 15 / React 19 / Tailwind)
│   ├── app/                  # Next.js App Router
│   ├── components/           # React components
│   └── lib/                  # Utilities
├── supabase/                 # Backend (Supabase + Edge Functions)
│   ├── functions/            # Deno edge functions
│   │   ├── chat-with-openai/ # OpenAI chat endpoint
│   │   ├── stream-*-*/       # Streaming endpoints
│   │   ├── oauth-*/          # OAuth flow handlers
│   │   └── _shared/          # Shared utilities
│   └── migrations/           # PostgreSQL migrations
└── .github/workflows/        # CI/CD (build, sign, release)
```

**Tech Stack:**
- **Desktop:** Swift, SwiftUI, Whisper.cpp, macOS 13+
- **Web:** Next.js 15, React 19, TypeScript, Tailwind CSS, Supabase SDK
- **Backend:** Supabase (PostgreSQL), Deno Edge Functions, OpenAI API, Deepgram API
- **DevOps:** GitHub Actions, Cloudflare R2, Xcode Cloud signing


---

## Architecture & Design Principles

These are default heuristics for making design decisions across the monorepo. When in doubt, prefer consistency with existing patterns over novel abstractions.

### Separation of Concerns

- **Separate by ownership + lifecycle**: Keep transport (routes, API handlers), orchestration (tRPC procedures), and domain rules in distinct layers when complexity warrants it.
- **Co-locate by lifecycle**: Feature-specific code lives together, not split by "type" (e.g., all task-related code in `router/task/`).
- **Boundary layers own error handling**: Domain utilities return data or throw specific errors; only boundary code (tRPC procedures, API routes) should catch and transform to `TRPCError` or HTTP responses.

### Minimal Coupling

- Keep modules self-contained with narrow public APIs; avoid importing "app state" into lower layers.
- Apply the Law of Demeter: depend on direct collaborators (passed dependencies), not transitive globals.
- When a module grows complex, prefer injecting dependencies (logger, db, external clients) rather than importing singletons so tests can substitute fakes.

### Right Tool for the Job

- Prefer existing primitives before writing new ones: check `packages/ui`, `packages/constants`, existing utilities.
- Use lookup objects/maps over `if (type === ...)` conditionals scattered across call sites when handling multiple cases.
- Match persistence + complexity to requirements: keep constants as code when static; use Drizzle for multi-tenant data.

### Fail-Safe by Default

- Validate at boundaries (Zod schemas for tRPC inputs, API route bodies) and handle invalid input with clear, user-visible errors.
- External API data is untrusted: handle missing fields, unknown enums, and unexpected shapes; prefer tolerant parsing + explicit fallbacks.
- Never swallow errors silently—at minimum log them with context.

### Avoid Premature Abstraction

- Start with the simplest correct solution; add complexity only when requirements demand it.
- Use the "three instances" heuristic for new helpers: don't abstract until you've seen the pattern three times.
- Don't introduce frameworks/DSLs for one-off cases.

### Keep Orchestrators Thin

- tRPC procedures and API route handlers should validate + delegate; complex domain rules live in utilities or service functions.
- A function should operate at one level of abstraction (orchestrate steps _or_ perform low-level work, not both).

### When to Extract a Service Layer

Use case-by-case judgment. Extract business logic from tRPC procedures when:

- The procedure exceeds ~50 lines of non-trivial logic
- The same logic is needed by multiple procedures or entry points
- Complex error handling with multiple failure modes
- You need to mock the logic independently for testing

Otherwise, inline logic in procedures is fine for straightforward CRUD.

---

## Coding Conventions

**What to log:**

- ✅ Entry/exit of significant operations
- ✅ External API calls (without sensitive data)
- ✅ Error conditions with context (IDs, relevant state)
- ❌ Sensitive data (tokens, passwords, PII)
- ❌ High-frequency operations in loops (batch the log)

---

## Code Smells to Avoid

| Smell                        | Symptom                                                                | Preferred Fix                                                     |
| ---------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Magic numbers                | Hardcoded `100`, `3`, `"linear"` in logic                              | Extract to `static let` constants or enums                        |
| Force unwrapping             | `value!` scattered throughout code                                     | Use `guard let`, `if let`, or nil-coalescing `??`                 |
| Massive view controllers     | ViewController handles UI + networking + business logic                | Extract to managers/services; use MVVM or similar pattern         |
| God objects                  | Single class doing validation + networking + persistence + UI updates  | Split into focused types with single responsibility               |
| Stringly-typed code          | Raw strings for keys, notifications, identifiers                       | Use enums, `Notification.Name` extensions, typed identifiers      |
| Callback hell                | Nested completion handlers 4+ levels deep                              | Use async/await or Combine publishers                             |
| Opacity                      | Reader can't understand intent within 30 seconds                       | Rename variables, extract named functions                         |
| Primitive obsession          | Passing raw `String` for IDs everywhere                                | Use type-safe wrappers or `RawRepresentable` structs              |
| Shotgun surgery              | One logical change requires edits in 5+ files                          | Co-locate related code; reconsider boundaries                     |
| Silent error swallowing      | `catch { }` or `try?` without handling                                 | At minimum log the error; prefer `do/catch` with explicit handling|
| Retain cycles                | Strong references in closures without `[weak self]`                    | Use `[weak self]` or `[unowned self]` appropriately               |
| Deep nesting                 | 4+ levels of if/guard/for nesting                                      | Early returns with `guard`, extract functions, invert conditions  |
| Boolean blindness            | `doThing(true, false, true)`                                           | Use structs with named properties or labeled parameters           |
| Implicit dependencies        | Singletons accessed via `.shared` throughout codebase                  | Inject dependencies via initializers for testability              |

---
