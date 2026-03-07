# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [0.5.0](https://github.com/unicornops/github-copilot-notify/compare/v0.4.8...v0.5.0) (2026-03-07)


### Features

* Add GNU GPLv3 license file ([de1a5c3](https://github.com/unicornops/github-copilot-notify/commit/de1a5c3aea63d70ea93fe03237a6765456422cd9))
* Add GNU GPLv3 license file ([7db78ad](https://github.com/unicornops/github-copilot-notify/commit/7db78ad82d53aec40f37c1e371c2277a969566bc))
* Switch to Release Please for automated releases and simplify build ([40df513](https://github.com/unicornops/github-copilot-notify/commit/40df51363b51136781fb8067c79531832c9cce79))
* Switch to Release Please for automated releases and simplify build workflow ([4646382](https://github.com/unicornops/github-copilot-notify/commit/464638294fec0318fdc445f6e70f01f691fe0953))


### Bug Fixes

* Add bootstrap-sha to release-please config ([435751e](https://github.com/unicornops/github-copilot-notify/commit/435751ea6cfcc3f72520023759445d5a04461920))
* Add bootstrap-sha to release-please config ([fc9ec4d](https://github.com/unicornops/github-copilot-notify/commit/fc9ec4dafda2412906a110ea7dad24036d405466))
* migrate release tooling from cocogitto to release-please ([1bc7571](https://github.com/unicornops/github-copilot-notify/commit/1bc7571ca9e1a51107a1cdf731da9b87d16553e6))
* migrate release tooling from cocogitto to release-please ([c6072dd](https://github.com/unicornops/github-copilot-notify/commit/c6072dd4259a7fda92149125664a2558b8446638))
* migrate release tooling to release-please test ([#28](https://github.com/unicornops/github-copilot-notify/issues/28)) ([02b20aa](https://github.com/unicornops/github-copilot-notify/commit/02b20aa7088b3a9750eaae2117e6bc8fecc5408d))
* paste (Cmd+V) not working in GitHub sign-in WebView ([8ff7eb0](https://github.com/unicornops/github-copilot-notify/commit/8ff7eb0cc78decfea3b97004a376ee2bb7015faf))
* Refactor release-please config ([c8d91af](https://github.com/unicornops/github-copilot-notify/commit/c8d91af97903d42c12a1822704441ed97e9e9063))

## v0.4.8 - 2026-03-02
#### Bug Fixes
- Remove certificate pinning and simplify session handling - (5f703eb) - Rob Lazzurs

- - -

## v0.4.7 - 2026-03-02
#### Bug Fixes
- Improve GitHub login flow: allow all HTTPS, clear cookies before - (9187538) - Rob Lazzurs

- - -

## v0.4.6 - 2026-03-01
#### Bug Fixes
- Migrate Keychain cookie storage to JSON format - (28c84af) - Rob Lazzurs

- - -

## v0.4.5 - 2026-03-01
#### Bug Fixes
- Fix session cookie detection logic in KeychainCookieStorage - (07339c4) - Rob Lazzurs

- - -

## v0.4.4 - 2026-03-01
#### Bug Fixes
- Improve session cookie detection and retry logic - (d1c6333) - Rob Lazzurs

- - -

## v0.4.3 - 2026-03-01
#### Bug Fixes
- Update certificate pinning and improve WebAuth window handling - (b9e25f6) - Rob Lazzurs

- - -

## v0.4.2 - 2026-03-01
#### Bug Fixes
- Post login crash - (0eee21f) - Rob Lazzurs

- - -

## v0.4.1 - 2026-03-01
#### Bug Fixes
- Remove @MainActor and use availability-aware app activation to fix build failure - (cb701ec) - copilot-swe-agent[bot]
- Fix crash after sign in by ensuring main actor isolation and proper app activation - (ff9105b) - copilot-swe-agent[bot]
#### Documentation
- update README to reflect current WebKit-based sign-in flow - (db62100) - copilot-swe-agent[bot]

- - -

## v0.4.0 - 2026-02-07
#### Features
- add App Store release workflow and build script - (5839d2e) - Rob Lazzurs

- - -

## v0.3.1 - 2026-01-30
#### Bug Fixes
- (**ui**) use emoji instead of icon in menu bar - (7c1125f) - Rob Lazzurs

- - -

## v0.3.0 - 2026-01-30
#### Features
- (**ui**) use icon instead of text prefix in menu bar - (3461db9) - Rob Lazzurs

- - -

## v0.2.7 - 2026-01-30
#### Bug Fixes
- (**security**) address low priority security audit findings - (d8f179b) - Rob Lazzurs

- - -

## v0.2.6 - 2026-01-30
#### Bug Fixes
- (**security**) address medium priority security audit findings - (5bab784) - Rob Lazzurs

- - -

## v0.2.5 - 2026-01-30
#### Bug Fixes
- (**security**) address high priority security audit findings - (375c003) - Rob Lazzurs

- - -

## v0.2.4 - 2026-01-29
#### Bug Fixes
- (**security**) enable app sandbox and migrate cookies to Keychain - (ec00c4c) - Rob Lazzurs

- - -

## v0.2.3 - 2026-01-25
#### Bug Fixes
- resolve SIGSEGV crash after successful sign-in - (47cc953) - Rob Lazzurs

- - -

## v0.2.2 - 2026-01-25
#### Bug Fixes
- handle spaces in volume name when parsing DMG mount point - (164e7af) - Rob Lazzurs

- - -

## v0.2.1 - 2026-01-25
#### Bug Fixes
- Second empty commit for build - (7f443c1) - Rob Lazzurs

- - -

## v0.2.0 - 2026-01-25
#### Features
- Empty commit for new version - (deb07af) - Rob Lazzurs
#### Bug Fixes
- resolve markdownlint violations in AGENTS.md and README.md - (86babfd) - Rob Lazzurs
- refactor CopilotSessionAPI to resolve SwiftLint function body - (b3d440a) - Rob Lazzurs
- resolve SwiftLint violations across codebase - (50bf77b) - Rob Lazzurs

- - -

## v0.1.0 - 2026-01-14
#### Features
- Initial commit - (ef5a71f) - Rob Lazzurs

- - -

Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).
