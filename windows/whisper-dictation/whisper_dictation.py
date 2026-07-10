#!/usr/bin/env python3
"""Native Windows local dictation with a global Ctrl+Shift+Space shortcut.

Press the shortcut once to start recording and once again to stop. The local
multilingual Whisper small model transcribes the captured audio and inserts the
result into the currently focused application using Unicode SendInput events.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import logging
import os
import queue
import signal
import struct
import sys
import threading
import time
import winsound
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

import keyboard
import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel


APP_ROOT = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "WhisperDictation"
CONFIG_PATH = APP_ROOT / "config.json"
DEFAULT_CONFIG: dict[str, Any] = {
    "model": "small",
    "device": "cpu",
    "compute_type": "int8",
    "cpu_threads": 8,
    "sample_rate": 16000,
    "hotkey": "ctrl+shift+space",
    "beam_size": 5,
    "model_dir": str(APP_ROOT / "models"),
    "log_dir": str(APP_ROOT / "logs"),
}

KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
INPUT_KEYBOARD = 1


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", ctypes.c_ushort),
        ("wScan", ctypes.c_ushort),
        ("dwFlags", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("dwExtraInfo", ctypes.c_void_p),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _anonymous_ = ("union",)
    _fields_ = [("type", ctypes.c_ulong), ("union", INPUT_UNION)]


def load_config() -> dict[str, Any]:
    config = DEFAULT_CONFIG.copy()
    if CONFIG_PATH.is_file():
        with CONFIG_PATH.open(encoding="utf-8") as file:
            loaded = json.load(file)
        if not isinstance(loaded, dict):
            raise ValueError(f"{CONFIG_PATH} must contain a JSON object")
        config.update(loaded)
    return config


def configure_logging(config: dict[str, Any]) -> None:
    log_dir = Path(config["log_dir"])
    log_dir.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(log_dir / "dictation.log", maxBytes=1_000_000, backupCount=3, encoding="utf-8")
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(threadName)s %(message)s",
        handlers=[handler],
    )


def model_reference(config: dict[str, Any]) -> str:
    """Use the downloaded snapshot after the first install, without a hub check."""
    local_snapshot = config.get("model_path")
    if local_snapshot and Path(str(local_snapshot)).is_dir():
        return str(local_snapshot)
    return str(config["model"])


def beep(frequency: int, duration_ms: int) -> None:
    try:
        winsound.Beep(frequency, duration_ms)
    except RuntimeError:
        logging.debug("Could not play status tone", exc_info=True)


def error_tone() -> None:
    for _ in range(2):
        beep(220, 100)
        time.sleep(0.06)


def type_unicode(text: str) -> None:
    """Insert Unicode text without changing the user's clipboard."""
    code_units = struct.unpack("<" + "H" * (len(text.encode("utf-16-le")) // 2), text.encode("utf-16-le"))
    inputs: list[INPUT] = []
    for code_unit in code_units:
        inputs.extend(
            [
                INPUT(type=INPUT_KEYBOARD, ki=KEYBDINPUT(0, code_unit, KEYEVENTF_UNICODE, 0, None)),
                INPUT(
                    type=INPUT_KEYBOARD,
                    ki=KEYBDINPUT(0, code_unit, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, 0, None),
                ),
            ]
        )

    if not inputs:
        return

    array_type = INPUT * len(inputs)
    sent = ctypes.windll.user32.SendInput(len(inputs), array_type(*inputs), ctypes.sizeof(INPUT))
    if sent != len(inputs):
        raise ctypes.WinError(ctypes.get_last_error())


class DictationService:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.sample_rate = int(config["sample_rate"])
        self.hotkey = str(config["hotkey"])
        self._recording = False
        self._stream: sd.InputStream | None = None
        self._chunks: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._jobs: queue.Queue[np.ndarray | None] = queue.Queue()
        self._worker = threading.Thread(target=self._transcribe_forever, name="transcription", daemon=True)

        model_dir = Path(config["model_dir"])
        model_dir.mkdir(parents=True, exist_ok=True)
        logging.info(
            "Loading Whisper %s locally with %s/%s",
            config["model"],
            config["device"],
            config["compute_type"],
        )
        self.model = WhisperModel(
            model_reference(config),
            device=str(config["device"]),
            compute_type=str(config["compute_type"]),
            cpu_threads=int(config["cpu_threads"]),
            num_workers=1,
            download_root=str(model_dir),
        )

    def _audio_callback(self, indata: np.ndarray, _frames: int, _time: Any, status: sd.CallbackFlags) -> None:
        if status:
            logging.warning("Audio callback status: %s", status)
        with self._lock:
            if self._recording:
                self._chunks.append(indata.copy())

    def toggle_recording(self) -> None:
        with self._lock:
            if self._recording:
                stream = self._stream
                self._recording = False
                self._stream = None
                audio = np.concatenate(self._chunks, axis=0).reshape(-1) if self._chunks else np.empty(0, dtype=np.float32)
                self._chunks = []
            else:
                try:
                    self._chunks = []
                    self._stream = sd.InputStream(
                        samplerate=self.sample_rate,
                        channels=1,
                        dtype="float32",
                        callback=self._audio_callback,
                    )
                    self._stream.start()
                    self._recording = True
                except Exception:
                    self._stream = None
                    logging.exception("Unable to start microphone recording")
                    error_tone()
                    return
                logging.info("Recording started")
                beep(880, 90)
                return

        if stream is not None:
            stream.stop()
            stream.close()
        logging.info("Recording stopped after %.2f seconds", len(audio) / self.sample_rate)
        beep(660, 90)
        if len(audio) < self.sample_rate // 4:
            logging.info("Discarded too-short recording")
            return
        self._jobs.put(audio)

    def _transcribe_forever(self) -> None:
        while True:
            audio = self._jobs.get()
            if audio is None:
                return
            try:
                segments, info = self.model.transcribe(
                    audio,
                    beam_size=int(self.config["beam_size"]),
                    language=None,
                    task="transcribe",
                    vad_filter=True,
                    condition_on_previous_text=False,
                    initial_prompt="Transcribe spoken German and English faithfully. Preserve the spoken language.",
                )
                text = " ".join(segment.text.strip() for segment in segments).strip()
                if not text:
                    logging.info("No speech detected")
                    error_tone()
                    continue
                logging.info("Transcribed %s (language %s)", len(text), info.language)
                type_unicode(text)
                beep(1047, 70)
            except Exception:
                logging.exception("Transcription failed")
                error_tone()

    def run(self) -> None:
        self._worker.start()
        keyboard.add_hotkey(self.hotkey, self.toggle_recording, suppress=True, trigger_on_release=True)
        logging.info("Dictation service ready; press %s to toggle recording", self.hotkey)
        while True:
            time.sleep(1)


def load_model_for_warmup(config: dict[str, Any]) -> None:
    model_dir = Path(config["model_dir"])
    model_dir.mkdir(parents=True, exist_ok=True)
    WhisperModel(
        model_reference(config),
        device=str(config["device"]),
        compute_type=str(config["compute_type"]),
        cpu_threads=int(config["cpu_threads"]),
        download_root=str(model_dir),
    )
    print(f"Whisper {config['model']} is downloaded and ready at {model_dir}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--warmup", action="store_true", help="Download and load the configured model, then exit")
    args = parser.parse_args()

    config = load_config()
    configure_logging(config)
    if args.warmup:
        load_model_for_warmup(config)
        return 0

    service = DictationService(config)

    def stop_service(_signum: int, _frame: Any) -> None:
        logging.info("Dictation service stopped")
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)
    service.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
