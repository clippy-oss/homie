# Changelog

All notable changes to the Homie macOS application will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **ALPHA SOFTWARE NOTICE**: This application is currently in alpha. Features may change without notice, and you may encounter bugs or incomplete functionality. Use at your own risk.

## [0.4.0-alpha.3] - 2026-01-02

> **WARNING**: This is an ALPHA release. It is subject to rapid changes, may contain bugs or incomplete features, and APIs/features may change without notice.

### Changed
- Consolidated permissions view for improved user experience
- Added version display beneath the download button

### Infrastructure
- Updated repository documentation and GitHub workflows for automated releases

## [0.4.0-alpha.2] - 2026-01-01

> **WARNING**: This is an ALPHA release. It is subject to rapid changes, may contain bugs or incomplete features, and APIs/features may change without notice.

### Added
- Toggle for enabling/disabling LocalLLM (default off)
- Keychain entitlements support

### Changed
- Delayed permission requests and display of current active permissions
- Moved model download to app support folder (no longer requires documents folder permission)
- Disabled per-session accessibility request

### Fixed
- Added SUFeedURL for Sparkle automatic updates

## [0.4.0-alpha.1] - 2025-12-30

> **WARNING**: This is an ALPHA release. It is subject to rapid changes, may contain bugs or incomplete features, and APIs/features may change without notice.

### Added
- Local LLM processing support using MLX framework for on-device inference
- Glass-effect response bubble view that expands when the LLM responds
- Response streaming with proper resource cleanup
- Deepgram and Whisper streaming transcription support
- Subscription management view
- Voice pipeline protocols for extensible audio processing
- Centralized permission management system
- Server-side OAuth flow and secure app secret storage

### Changed
- Renamed OpenAIManager to LLMService for provider-agnostic architecture
- Centralized authentication and entitlement gating
- Centralized feature and tiered entitlements management
- Replaced custom authentication session storage with Supabase SDK
- Improved model loading display text to reflect disk vs memory loading states
- Replaced print statements with rotating file logging system
- Various UI/UX improvements including menu bar, colors, and styling enhancements

### Fixed
- Premature logout issue during token refresh
- Token refresh now waits properly without clearing auth context
- Remote OAuth flow for Google Calendar integration

## [1.0.1] - 2025-11-21

### Added
- Automatic update system via Sparkle framework
- Users can now receive updates automatically

### Notes
- Initial test version to verify the update system

## [1.0.0] - 2025-11-01

### Added
- Initial release of Homie macOS application
- Voice-activated AI assistant
- Global keyboard shortcuts
- Menu bar integration

---

[0.4.0-alpha.3]: https://github.com/homie-clippy/homie_project/releases/tag/v0.4.0-alpha.3
[0.4.0-alpha.2]: https://github.com/homie-clippy/homie_project/releases/tag/v0.4.0-alpha.2
[0.4.0-alpha.1]: https://github.com/homie/releases/tag/v0.4.0-alpha.1
[1.0.1]: https://github.com/homie/releases/tag/v1.0.1
[1.0.0]: https://github.com/homie/releases/tag/v1.0.0
