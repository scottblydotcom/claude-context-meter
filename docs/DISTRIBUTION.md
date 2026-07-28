# Distribution

How Claude Context Meter reaches users, what's deliberately not done yet, and what unblocks the rest.

## Current channel: GitHub Releases only

Each release publishes a `ClaudeContextMeter-<version>.dmg` attached to a
[GitHub Release](https://github.com/scottblydotcom/claude-context-meter/releases). There is no
package manager, no auto-update, and no App Store listing.

Release history is complete as of 2026-07-27: `v1.0`, `v1.1.0`, `v1.2.0`, `v1.3.0`, `v1.4.0`.
`v1.1.0` and `v1.2.0` are notes-only (no attached binary) — `v1.1.0` never had one, and `v1.2.0` was
backfilled two months after its git tag.

### The "Packages" section on the repo page is expected to be empty

GitHub's sidebar **Packages** panel refers to [GitHub Packages](https://github.com/features/packages),
a registry for npm / RubyGems / Maven / NuGet / Docker artifacts. It does not host macOS app bundles
or DMGs and has no format that fits a signed Mac application. **Releases** and **Packages** are
separate features; this project uses Releases. "No packages published" is the correct steady state
and should not be read as a missing release.

## Code signing status

Builds are signed with a local **Apple Development** certificate and are **not notarized**.
Notarization requires a paid Apple Developer Program membership ($99/yr), which is a deliberate
deferral until the app has enough users to justify it.

Consequence: macOS Gatekeeper blocks the app on first launch. Every release's notes carry the
Privacy & Security → *Open Anyway* walkthrough, plus the `xattr -dr com.apple.quarantine` shortcut.

## Homebrew: blocked on notarization, not just popularity

Evaluated 2026-07-27. Two independent blockers, in order of severity:

### 1. Gatekeeper (the hard blocker)

Homebrew's [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) policy states casks must not
require Gatekeeper "to be disabled or bypassed." An unsigned, un-notarized app requires exactly that.

This used to be worked around with `brew install --cask --no-quarantine`. That flag has been
[deprecated with no replacement](https://github.com/Homebrew/brew/issues/20755) and removed —
verified against Homebrew 6.0.11 on 2026-07-27, where `brew install --help` no longer lists any
quarantine option. Homebrew's stated reason is that it now requires casks to satisfy Gatekeeper.

This blocker applies to a **personal tap too**, not just `homebrew/cask`. A tap is unmoderated, so a
cask *can* be published there — but `brew install` would place a quarantined app the user still has
to hand-approve, which is a worse experience than downloading the DMG directly, wrapped in a command
that implies it isn't. Shipping that would be misleading.

### 2. Notability (applies only to `homebrew/cask`)

Submissions to the official `homebrew/cask` are rejected below **30 forks, 30 watchers, or 75 stars**.
This repo is at 1 star / 0 forks / 0 watchers as of 2026-07-27, so official-cask submission is not on
the table regardless of signing. A personal tap has no such requirement.

### Decision

**Do not ship a Homebrew tap yet.** Revisit when a Developer ID certificate exists and releases are
notarized — at which point a personal tap becomes viable immediately, and `homebrew/cask` becomes
viable if the repo clears the notability bar.

Tracked as [`claude-context-meter-vwl`](https://github.com/scottblydotcom/claude-context-meter).

### Ready-to-use cask (for when notarization lands)

Publish as `scottblydotcom/homebrew-tap` → `Casks/claude-context-meter.rb`, installable with
`brew install --cask scottblydotcom/tap/claude-context-meter`. The `sha256` below is the real digest
of the current v1.4.0 asset; regenerate per release with
`shasum -a 256 ClaudeContextMeter-<version>.dmg`.

```ruby
cask "claude-context-meter" do
  version "1.4.0"
  sha256 "d4b1bab88cd7cdb3059c0001fc6118b1499b227afc8b7d8d7ed5f78092c61b13"

  url "https://github.com/scottblydotcom/claude-context-meter/releases/download/v#{version}/ClaudeContextMeter-#{version}.dmg"
  name "Claude Context Meter"
  desc "Menu bar app showing Claude Code token usage"
  homepage "https://github.com/scottblydotcom/claude-context-meter"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "ClaudeContextMeter.app"

  zap trash: [
    "~/Library/Preferences/com.scottbly.ClaudeContextMeter.plist",
    "~/Library/Caches/com.scottbly.ClaudeContextMeter",
  ]
end
```

Untested — it cannot be validated end-to-end (`brew audit --cask --new`) until there is a notarized
build to point it at.

## Other channels considered

| Channel | Status |
|---|---|
| Mac App Store | Not viable — the app reads arbitrary paths under `~/.claude/`, which App Sandbox forbids. This is architectural, not a deferral. |
| Sparkle auto-update | Not started. Would need a signed appcast; same Developer ID dependency. |
| GitHub Packages | Not applicable — no artifact format for Mac apps. |
