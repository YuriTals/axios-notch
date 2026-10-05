<div align="center">
    <img src="docs/app-icon.png" width=200 height=200>
    <h1>Axios Notch</h1>
    <b>English</b> · <a href="README.pt-BR.md">Português (Brasil)</a>
</div>

<p align="center">
  Axios Notch turns your MacBook's notch into a panel for your coding agents.<br>
  It shows how much of your <b>Claude</b> and <b>Codex</b> plan you have used, opens terminals<br>
  without leaving what you are doing, and tells you when an answer is ready.
</p>

<p align="center">
  <img src="docs/screenshots/seletor.png" width="380" alt="Active tools picker">
  <img src="docs/screenshots/uso.png" width="380" alt="Claude plan usage">
</p>

<p align="center">
  <a href="https://github.com/YuriTals/axios-notch/releases/latest"><img src="https://img.shields.io/badge/download-latest-brightgreen?style=flat-square" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/requirements-macOS%2014%2B%20%C2%B7%20Apple%20Silicon-fa4e49?style=flat-square" alt="Requirements">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square" alt="License"></a>
  <a href="https://buymeacoffee.com/axiosdevteam"><img src="https://img.shields.io/badge/Buy%20Me%20A%20Coffee-axiosdevteam-FFDD00?style=flat-square&logo=buy-me-a-coffee&logoColor=000000" alt="Buy Me A Coffee"></a>
  <a href="https://ko-fi.com/axiosdevteam"><img src="https://img.shields.io/badge/Ko--fi-axiosdevteam-FF5E5B?style=flat-square&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

## Highlights

- **Active tools:** Claude, Codex, Antigravity, up to two tools of your own and a Terminal, one click away.
- **Plan usage:** click Claude, Codex or Antigravity to see that CLI's 5-hour and weekly usage. Antigravity shows its account's highest quota utilization and local token/cache totals; forecasts and alerts at 80% and 90% remain available for Claude and Codex.
- **Persistent terminals** inside the notch: copy the last answer, and paste or drag images, files and folders.
- **Notices:** answer ready and approval requests, with an optional macOS notification.
- **Multiple monitors, themes, bundled Nerd Fonts**, English and Portuguese, and an optional Liquid Glass look (macOS 26+).

<p align="center">
  <img src="docs/screenshots/terminal.png" width="380" alt="Terminal inside the notch">
  <img src="docs/screenshots/ajustes-experiencia.png" width="380" alt="Settings">
</p>

## Install

1. Download `AxiosNotch-<version>.dmg` from the [Releases page](https://github.com/YuriTals/axios-notch/releases/latest) and drag the app to **Applications**.
2. Open Axios Notch. It has no Dock icon: it lives in the notch and in an asterisk in the menu bar.

The app is not notarized by Apple yet, so macOS may warn you the first time. Go to **System Settings › Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Axios Notch.app"
```

## Requirements

- macOS 14 or later, on a Mac with Apple Silicon. Intel Macs need to build from source.
- The `claude`, `codex` and `agy` CLIs installed and signed in, to use each tool.

## Privacy

Everything happens on your machine. To show plan usage, the app reads the login the CLIs already keep (Claude Code's Keychain item and `~/.codex/auth.json`) and only contacts `api.anthropic.com` and `chatgpt.com`, about every 60 s. It does **not store, log or refresh** tokens. The app also asks `api.github.com` for the latest release (at launch and about every 12 h) to offer updates; you can turn this off in Settings. Those two endpoints are undocumented and may change without notice. The feedback button opens your mail app with versions and preferences, never tokens, conversations or folders.

## Build

```sh
swift run                   # development mode
scripts/build-app.sh        # builds "build/Axios Notch.app"
scripts/make-dmg.sh         # builds build/AxiosNotch-<version>.dmg
swift test
```

## License

Axios Notch is free software under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). Third-party logos, names and fonts are not covered by it; see the disclaimer below.

## Disclaimer

Axios Notch is an independent project and is not affiliated with, endorsed by or sponsored by Anthropic, OpenAI, Google or Apple. Claude, Claude Code, Codex, ChatGPT, OpenAI, Antigravity, Gemini, Google, macOS and Apple are trademarks of their respective owners, and the logos and names shown in the app and in this repository belong to them, with all rights reserved to their owners. The bundled Nerd Fonts, and the fonts they are based on, belong to their authors and are distributed under their own licenses (SIL OFL 1.1; Hack under MIT), included in `Sources/AxiosNotch/Resources/Fonts/licenses/`.
