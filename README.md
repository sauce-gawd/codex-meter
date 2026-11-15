# Codex Meter

**My first AI-assisted project:** a lightweight native macOS menu bar app that keeps Codex usage limits a click away.

Built with help from OpenAI Codex, using SwiftUI, Swift Charts, and Foundation. No third-party dependencies or hosted backend.

## Why I built it

I wanted to see my remaining allowance without opening a chat or digging through settings. Codex Meter puts a percentage in the Mac menu bar and opens a compact panel with the details.

## Features

- Remaining allowance for the usage windows returned by Codex, including five-hour and weekly limits when available.
- Reset countdowns, with the exact reset date available on hover.
- Latest reported daily token count and a chart of up to seven reported days.
- Refresh on demand, after wake, and every three minutes by default.
- Settings for refresh frequency, Codex executable location, and optional launch at login.
- Clear connection errors and stale-data labels.

The menu bar percentage represents the main usage window. Click it to see all returned windows. This initial version does not include a Control Centre extension.

## Requirements

- macOS 14 or newer.
- Apple Command Line Tools or Xcode, with a Swift compiler.
- Codex installed and signed in with a ChatGPT account. API-key-only sign-in does not expose subscription limits.

## Build and run

```sh
git clone https://github.com/sauce-gawd/codex-meter.git
cd codex-meter
CODEX_METER_APP_OUTPUT="$HOME/Applications/Codex Meter.app" zsh scripts/build.sh
open "$HOME/Applications/Codex Meter.app"
```

The build script compiles the app, creates its icon, and applies an ad hoc local signature. Using the local Applications folder avoids synced-folder metadata interfering with signing.

Click the gauge in the menu bar to open the panel. Open the gear menu to change settings or quit. Launch at login is off by default; enable it only after placing the app in a permanent location. macOS may ask you to approve it in Login Items.

If Codex cannot be found, use **Choose Codex executable…** in the gear menu. You can select the executable or the ChatGPT/Codex app containing it.

To build into the project directory instead, run `zsh scripts/build.sh`; the result is `dist/Codex Meter.app`.

## How it works

The app opens a short-lived local Codex app-server connection and calls the documented metadata methods `account/read`, `account/rateLimits/read`, and `account/usage/read`. It closes the connection after each refresh.

It does not start model turns, generate responses, create chats, or redeem earned resets. Reading usage metadata is expected to have no impact on model allowance; this has not been independently verified as a billing guarantee.

Codex handles its existing authentication. Codex Meter does not parse or copy credentials, send data to its own backend, or save usage readings to disk. The latest successful reading stays in memory; UserDefaults stores only app preferences and an optional executable path. Codex itself may maintain its own authentication and runtime state.

## Understanding the numbers

- Quota windows use durations provided by the service. A five-hour window is not a daily quota.
- Token totals and remaining allowance are separate measures; the app does not convert tokens into an assumed quota.
- Daily token activity uses the service reporting date, which can lag today or use a different timezone.
- Missing metrics appear as unavailable. Missing days are not filled with invented zeros.
- After a reset countdown expires, the app refreshes to confirm allowance rather than assuming it has replenished.

## Checks and preview

```sh
zsh scripts/test.sh
"$HOME/Applications/Codex Meter.app/Contents/MacOS/CodexMeter" --check-connection
```

Nine checks cover allowance calculations, service-provided window labels, reset handling, multiple buckets, missing data, and a simulated read-only protocol connection. The live connection check prints availability without credentials or raw account data.

For a clearly labelled sample-data panel, run the executable with `--preview`. Export a sample screenshot with `--render-preview /absolute/path/preview.png`.

The scripts use Apple's compiler directly, so a full Xcode install is not required. A Swift package manifest is also included for standard Xcode/SwiftPM environments.

## Project status

This is an early personal project, developed and refined with AI assistance. The initial version has been built and checked on an Apple Silicon Mac running macOS 26.5.1; other environments have not yet been verified.

The app is locally signed, not Developer ID signed or notarized. It is currently distributed as source. Codex app-server availability and returned fields can vary by version and account.

Created by [@sauce-gawd](https://github.com/sauce-gawd), with AI assistance from OpenAI Codex. This is an independent project, not an official OpenAI product.

[Codex app-server documentation](https://learn.chatgpt.com/docs/app-server)
