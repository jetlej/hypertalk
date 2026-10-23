<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/icon-dark.png">
    <img src="docs/assets/icon.png" width="96" alt="hypertalk">
  </picture>
</p>

# hypertalk

Hold `fn`, speak, release. Your words appear at the cursor. On-device dictation for macOS.

## 1. Install

Hypertalk is a fork of [Parrot](https://github.com/humanitas-labs/parrot) with hands-free recording, auto-learned vocabulary, and every setting in the Settings window. There are no prebuilt releases yet; build it from source (section 6), which installs Hypertalk.app.

Requires macOS 14+ on Apple Silicon. Turn on Hypertalk when macOS asks for Accessibility and the microphone. The first start downloads the speech model, NVIDIA Parakeet v2 (about 600 MB).

## 2. Usage

1. Click into any text field.
2. Hold `fn` and speak. A small pill at the bottom of the screen shows the mic is live. On a keyboard where `fn` does nothing (Logitech and most third-party keyboards), choose another key under **Hotkey** in **Settings…**: left or right Option, Command, Control, or Shift. The change applies from the next press.
3. Release. The transcript is pasted at the cursor, usually within 200–300 ms, and your clipboard is restored.

**Hands-free:** double-tap the hotkey and let go; Hypertalk keeps listening (the pill shows a padlock) until you press the key again. Under **Hands-free** in Settings, choose **Single tap** to lock with one tap instead, or **Off**.

**Focus changes:** if you switch apps or fields while dictating, the transcript goes to the clipboard instead of pasting. Turn on **Paste when focus changes** in Settings to paste wherever the cursor is.

Choose **Launch at login** in **Settings…** to start Hypertalk with your Mac. A tap shorter than 0.3 s, or a hold with another modifier, is ignored, so shortcuts on the hotkey still work. If `fn` is mapped to input source or emoji, `hypertalk doctor` shows how to fix it.

To dictate in another language, choose a multilingual model in Settings (⌘, from the menu), then either one Language or Automatic. Automatic detects which of the languages under **Languages** each dictation is in, and never picks one you haven't listed. The list starts as your Mac's languages.

## 3. Dictionary

Add your names and technical terms to `~/.config/hypertalk/dictionary`, a plain-text table of each word and what the model writes instead, and Hypertalk spells them your way. **Open Dictionary File** in Settings opens it. Edits apply on the next dictation. See [docs/dictionary.md](docs/dictionary.md).

Hypertalk also learns words on its own: when you fix a name or term right after dictating it ("ver cell" → "Vercel"), it adds the word to the dictionary, with what it misheard as the replacement, and says so in the pill. It keeps names and uncommon terms, and skips everyday words, capitalization fixes, rewrites, numbers, paths and code. Learned words are listed in Settings, where removing one also stops it from being learned again. Field text is only read over Accessibility on your Mac for 45 seconds after a dictation, is never logged, and only the learned word is saved. Turn it off with **Learn new words**.

## 4. CLI

| Command | What it does |
|---|---|
| `hypertalk` | Run in the foreground (^C to quit) |
| `hypertalk setup` | One-time setup: permissions and model download |
| `hypertalk doctor` | Check permissions, and the `fn` key setting when the hotkey is `fn` |
| `hypertalk install --launch-at-login` | Start Hypertalk at login |
| `hypertalk install --cli` | Link `/usr/local/bin/hypertalk` to Hypertalk.app |
| `hypertalk install --uninstall` | Stop launching at login and remove logs |
| `hypertalk models list` | List available models |
| `hypertalk --model whisper-large-v3-turbo` | Larger, multilingual model |
| `hypertalk --hotkey right-option` | Use another key for this run only; Settings… changes the saved key |
| `hypertalk --no-overlay` | Hide the recording pill |
| `hypertalk --inject-mode type-unicode` | Type instead of paste (leaves the clipboard alone) |

## 5. How it works

FluidAudio runs NVIDIA Parakeet (or WhisperKit runs Whisper, if you pick a Whisper model) on the Apple Neural Engine via CoreML, AVAudioEngine captures the mic, a CGEventTap watches the hotkey, and a synthesized ⌘V pastes the result. Nothing leaves your Mac, and logs never contain what you said. See [docs/architecture.md](docs/architecture.md).

## 6. Build from source

```sh
swift build -c release && swift test
scripts/dev-install.sh      # build, sign, install Hypertalk.app, link the CLI
```

## 7. License

[MIT](LICENSE)
