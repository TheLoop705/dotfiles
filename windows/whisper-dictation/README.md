# Local Windows Whisper dictation

This is a native Windows background service. It records the default Windows
microphone, runs the open-source multilingual Whisper `small` model locally,
and types the result into the focused application. No audio is sent to a cloud
service.

## Why this model and runtime

`small` is the multilingual 244M-parameter Whisper checkpoint, unlike
`small.en`, so it handles both German and English. The service uses
faster-whisper with CPU INT8: it is dependable on a fresh Windows setup and is
fast for short dictation on a modern multi-core CPU without depending on a
specific CUDA toolkit or GPU DLL version.

## Install

From normal PowerShell:

```powershell
& "$HOME\dotfiles\windows\whisper-dictation\install.ps1"
```

The installer creates a private virtual environment and data directory at
`%LOCALAPPDATA%\WhisperDictation`, downloads the model there once, starts the
service immediately, and registers a **Whisper Dictation** Task Scheduler task
for this user's logon. It then runs from the downloaded model snapshot, so
later sign-ins and all transcription stay local. The task restarts the service
up to three times after a failure.

## Use

- `Ctrl+Shift+Space` — start recording.
- `Ctrl+Shift+Space` again — stop, transcribe, and insert the text into the
  previously focused control.
- A high tone means recording started, a low tone means it stopped, and a short
  high tone confirms text was inserted. Two low tones signal an error or no
  speech.

The service uses the default Windows microphone. Change the default input in
**Settings → System → Sound → Input**. It automatically identifies German or
English for each recording; mixed-language speech works best in short segments.

## Files and operations

- Model/cache: `%LOCALAPPDATA%\WhisperDictation\models`
- Configuration: `%LOCALAPPDATA%\WhisperDictation\config.json`
- Logs: `%LOCALAPPDATA%\WhisperDictation\logs\dictation.log`
- Login task: Task Scheduler → Task Scheduler Library → **Whisper Dictation**

The text insertion uses Windows Unicode input events, not the clipboard, so
your clipboard contents are preserved. Windows prevents a normal user-level
process from typing into an elevated (Run as administrator) app; use a normal
window for dictation in that case.

To stop it temporarily:

```powershell
Stop-ScheduledTask -TaskName 'Whisper Dictation'
```

To start it again:

```powershell
Start-ScheduledTask -TaskName 'Whisper Dictation'
```
