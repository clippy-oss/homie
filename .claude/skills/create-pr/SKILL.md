---
name: create-pr
description: use to create github pull requests (PRs)
---
# Persona & Goal


# Instructions

Write PR bodies that are:
- reviewer-friendly (fast to understand + verify)
- future-friendly (captures the why + constraints)
- proportionate (no filler, no "N/A" padding)
- honest about validation (if you didn't test something, say so and why)

A good PR description answers:
1. **Summary** - what changed (1-3 bullets)
2. **Why / Context** - why this exists, what problem it solves
3. **How It Works** - brief explanation of the approach (for non-trivial changes)
4. **Manual QA** - specific scenarios you validated, including edge cases
5. **Testing** - build verification and manual testing performed
6. **Risks / Rollout / Rollback** - only when the change has meaningful risk

IMPORTANT:
- When on `main`, ALWAYS create a branch first before committing. Never push directly to `main`.
- If there is an ExecPlan, link it in the PR body and call out deltas (what shipped, what deferred).

# Workflow (creating the PR)

Use the GitHub CLI (`gh`) to create PRs.

## 1. Inspect the current changes
- `git status`, `git diff`, `git log -5`

## 2. Review changes against codebase standards (CRITICAL GATE)

Before proceeding, review the diff against the relevant standards and best practices documented in:

**Always check:**
- `AGENTS.md` (root) - coding standards, architecture principles

Create an internal checklist from AGENTS.md and review code against it.

### If discrepancies are found: STOP and report

Do NOT proceed with the PR. Instead, present findings to the user:

    ## Standards Review: Issues Found

    I reviewed the changes against our codebase standards and found the following discrepancies:

    ### 1. [Issue Category]
    **File(s):** `path/to/file.swift`
    **Standard:** [Reference the specific rule from AGENTS.md]
    **Current code:**
        // problematic code snippet
    **Issue:** [Explain why this doesn't align]

    **Proposed fix:**
        // suggested fix

    ### 2. [Next issue...]
    ...

    ---

    **Options:**
    1. **Fix all** - I'll update the code to align with standards before creating the PR
    2. **Fix some** - Tell me which issues to fix and which to skip (with justification for the PR)
    3. **Proceed anyway** - Create the PR as-is (I'll note the deviations in "Known Limitations")
    4. **Discuss** - Let's talk through specific items if you disagree with a standard

    Which would you like to do?

**Only proceed to step 3 after user confirms.**

## 3. Ensure you are on a feature branch
- Never commit directly to `main`.
- If starting from `main`: `git switch -c <feature-branch-name>`

## 4. Move ExecPlan to done (if applicable)
- If this PR completes an ExecPlan:
  `git mv plans/<plan-name>.md plans/done/<plan-name>.md`
- Fill in `Outcomes & Retrospective` first.
- Update the PR body link to point at the `done/` path.
- Skip if there is no ExecPlan or it spans multiple PRs.

## 5. Stage and commit changes
- `git add <paths>`
- Make commits that tell the story; avoid dumping unrelated changes in one commit.

## 6. Push the branch
- First push: `git push -u origin <feature-branch-name>`

## 7. Create the PR with `gh`
- Use a HEREDOC so the body stays formatted:

    gh pr create \
      --title "<PR title>" \
      --body "$(cat <<'EOF'
    <paste PR body from a template below>
    EOF
    )"

# PR Titles

Prefer titles that front-load impact. Use type/scope only if the team finds it helpful.

Good:
- `fix: prevent duplicate permission prompts on launch`
- `feat: add keyboard shortcut for quick capture`
- `refactor: consolidate Supabase auth flow`

Avoid:
- "WIP"
- "Fixes"
- "Changes"

# PR Body Templates (scale to size + risk)

Pick the smallest template that makes review easy. Delete sections that don't apply—don't leave "N/A".

## When to use which

Use **Small** when:
- low risk, easy diff, no deploy coordination
- behavior change is minimal or none
- docs-only or comment-only changes

Use **Standard** for most PRs:
- behavior changes, multi-file changes, non-obvious logic, or anything needing context

Use **High-risk/Complex** when any of these are true:
- changes to code signing, entitlements, or notarization
- release script or CI workflow changes
- auth/security changes
- large blast radius / hard-to-reverse behavior

## Small PR template

    ## Summary
    - ...

    ## Testing
    - Built in Xcode (Cmd+B) - no errors
    - Manual: ... (if behavior changed)

    ## Notes (optional)
    - ...

> For docs-only changes, "Testing: reviewed locally" is sufficient.
> If this small PR changes behavior, add 1-2 QA items under "Manual:" covering the happy path.

## Standard PR template

    **Links (optional)**
    - ExecPlan: `plans/<plan-name>.md`
    - Issue: <link>

    ## Summary
    - ... (1-3 bullets: what changed and why it matters)

    ## Why / Context
    ...

    ## How It Works

    Brief explanation of the approach—what the code does at a high level.
    Helps reviewers understand before diving into the diff.
    (Omit for trivial changes where the diff is self-explanatory.)

    ## Manual QA Checklist

    > Use categories appropriate to the change. See QA Categories section below.

    - [ ] ...
    - [ ] ...
    - [ ] ...

    ## Testing
    - Built in Xcode (Cmd+B) - no build errors
    - Ran app and tested feature manually
    - If touching release: `./homie/release/release.sh --skip-notarize`

    ## Design Decisions (optional)
    - **Why X instead of Y**: Explain trade-offs when you chose between viable approaches.

    ## Known Limitations (optional)
    - Document known gaps, edge cases not handled, or behavior that may surprise users/reviewers.

    ## Follow-ups (optional)
    - Work intentionally deferred to keep this PR focused.

    ## Risks / Rollout (omit if low-risk)
    - Risk:
    - Rollout:
    - Rollback:

## High-risk/Complex PR template

For PRs bundling multiple features, use Part headers to organize:

    **Links**
    - ExecPlan: `plans/<plan-name>.md`
    - Issue: <link>

    ## Summary

    This PR bundles [N] related features:

    1. **Feature A** - Brief description
    2. **Feature B** - Brief description

    **Also includes:**
    - Minor enhancement X
    - Minor enhancement Y

    ---

    ## Part 1: Feature A

    ### Why
    ...

    ### What / How
    ...

    ### Key Decisions

    | Decision | Choice | Rationale |
    |----------|--------|-----------|
    | ... | ... | ... |

    ---

    ## Part 2: Feature B

    ### Why
    ...

    ### What / How
    ...

    ---

    ## Manual QA Checklist

    ### Feature A
    - [ ] ...
    - [ ] ...

    ### Feature B
    - [ ] ...
    - [ ] ...

    ### Integration / Cross-feature
    - [ ] ...

    ---

    ## Testing
    - Built in Xcode (Cmd+B) - no build errors
    - Ran app and tested all features manually
    - Built release DMG: `./homie/release/release.sh --skip-notarize`
    - Verified code signing: `codesign -dv --verbose=4 <path-to-app>`

    ## Design Decisions
    - **Why X instead of Y**: ...

    ## Known Limitations
    - ...

    ## Future Work
    - ...

    ## Deployment / Rollout
    - Feature flags/config:
    - Ordering constraints:
    - Rollout steps:

    ## Rollback
    - Stop new impact:
    - Revert code/config:

    ## Files Changed

    ### New Files
    - `path/to/new-file.swift` - Description

    ### Modified Files
    - `path/to/file.swift` - What changed

# QA Categories by Domain

Use these as templates for the Manual QA Checklist section. Pick categories appropriate to your change.

## macOS App

### General
- [ ] App launches without errors
- [ ] No console errors in Xcode debug console
- [ ] Feature works after app restart
- [ ] App correctly handles permission requests (accessibility, microphone, etc.)

### Code Signing & Distribution
- [ ] App is properly signed (`codesign -dv --verbose=4 /path/to/app`)
- [ ] App passes Gatekeeper (`spctl --assess -vvv /path/to/app`)
- [ ] DMG is properly signed and notarized (if touching release)
- [ ] Sparkle auto-update works (if touching update logic)

### UI & SwiftUI
- [ ] Views render correctly at different window sizes
- [ ] Dark mode / light mode appearance correct
- [ ] Keyboard shortcuts work
- [ ] Menu bar items functional
- [ ] Animations smooth, no visual glitches

### Permissions & Entitlements
- [ ] Accessibility permission requested when needed
- [ ] Microphone permission requested when needed
- [ ] App functions gracefully when permissions denied
- [ ] No crashes when permissions revoked while app running

### Supabase Integration
- [ ] Authentication flows work (sign in, sign out)
- [ ] Data syncs correctly to/from Supabase
- [ ] Handles network errors gracefully
- [ ] Offline behavior handled appropriately

### Release Workflow
- [ ] `release.sh` completes successfully
- [ ] DMG mounts and app runs from it
- [ ] Notarization succeeds (or --skip-notarize for local testing)
- [ ] Version number updated correctly

## Security & Privacy

### Data Handling
- [ ] No sensitive data in logs (tokens, passwords, PII)
- [ ] Error messages don't leak internal details
- [ ] No secrets committed to repo
- [ ] Keychain used for sensitive storage

## Performance & UX

### Perceived Performance
- [ ] No jank on navigation or interactions
- [ ] Loading states appear quickly
- [ ] App startup time reasonable
- [ ] Memory usage stable (no leaks)

## CI/CD Workflows

### GitHub Actions
- [ ] Workflow triggers correctly (push, tag, manual)
- [ ] Build job completes successfully
- [ ] Artifacts uploaded correctly
- [ ] Secrets accessed properly (not exposed in logs)

# Optional add-ons (use only when they add signal)

- **Screenshots / recordings** for UI changes (before/after when helpful).
- **Keyboard shortcuts table** for changes that add shortcuts.
- **Decision tables** for changes with multiple trade-offs.
- **Files changed summary** for large PRs (helps reviewers navigate).
- **Plan deltas** when an ExecPlan exists (what deviated and why).
- **"How to review" hints** for large diffs (suggested review order, key files to focus on).

# Example (Standard - macOS Feature)

    **Links**
    - ExecPlan: `plans/done/permission-manager-exec-plan.md`

    ## Summary
    - Add centralized permission management for accessibility and microphone access.
      Users now see a single settings pane to grant/revoke all permissions.

    ## Why / Context
    The app requires multiple macOS permissions. Currently users must navigate to
    System Settings manually. A centralized permission manager improves onboarding.

    ## How It Works
    - New `PermissionStore` class manages permission state using `@Observable`
    - SwiftUI view observes permission changes and updates UI
    - Uses `AXIsProcessTrusted()` and `AVCaptureDevice.authorizationStatus()`
    - "Grant" buttons open the correct System Settings pane via URL schemes

    ## Manual QA Checklist

    ### Permission Settings
    - [ ] Settings window shows all required permissions
    - [ ] Permission status updates in real-time when granted externally
    - [ ] "Grant" button opens correct System Settings pane
    - [ ] Works on fresh install (no permissions granted)

    ### App Behavior
    - [ ] App gracefully handles denied permissions
    - [ ] Features requiring permissions are disabled when not granted
    - [ ] No crashes when permissions revoked while app running

    ## Testing
    - Built in Xcode (Cmd+B) - no errors
    - Ran on macOS 14.0 and 15.0 to verify API compatibility
    - Tested with permissions granted and denied

    ## Design Decisions
    - **Why PermissionStore vs individual checks**: Centralizes all permission logic,
      makes testing easier, and provides single source of truth for UI.

    ## Follow-ups
    - Add screen recording permission check (deferred to keep PR focused)

# Agent Constraints

- Never update `git config`.
- Only push/create a PR when explicitly asked.
- Use HEREDOCs for multi-line commit and PR messages.
- You may run git commands in parallel when it is safe and helpful.
- For any change with meaningful risk (availability, data integrity, security, broad customer impact), include a concrete rollback plan.
- **Standards review is a blocking gate** - do not skip step 2 or proceed silently if issues are found.
