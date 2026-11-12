"""Nonblocking Unicode name-rule companion adapter; never reads ChatGPT UI."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import uuid

MAX_BYTES = 131072
MAX_ENTRIES = 128
MAX_UNITS = 512
SUFFIX = " — ChatGPT"


def encode_sources(rows):
    """CTS1 contains verified raw names only, with explicit little-endian lengths."""
    chunks, total = [], 8
    for raw in rows:
        data = raw.encode("utf-16-le")
        if len(data) // 2 > MAX_UNITS or len(chunks) >= MAX_ENTRIES:
            continue
        if total + 4 + len(data) > MAX_BYTES:
            break
        chunks.append(struct.pack("<I", len(data) // 2) + data)
        total += 4 + len(data)
    return b"CTS1" + struct.pack("<I", len(chunks)) + b"".join(chunks)


def atomic_bytes(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class NameReplacement:
    """One caller-owned format child, independent of source reader scheduling."""
    def __init__(self, settings_path, emit=None, *, rules_path=None, helper=None,
                 source_file=None, launch=None, clock=None, caption_mode=False):
        self.caption_mode = bool(caption_mode)
        self.runtime = Path(settings_path).resolve().parent
        self.sources_path = self.runtime / "title-rule-sources.bin"
        self.rules_path = Path(rules_path or Path(os.environ.get("LOCALAPPDATA", Path.home())) /
                               "ChatGPT-TitleSync" / "title-rules.json").resolve()
        source = Path(source_file or __file__).resolve()
        self.roots = [Path(sys.executable).resolve().parent, source.parents[2]]
        self.helper_override = Path(helper).resolve() if helper else None
        self.launch = launch or subprocess.Popen
        self.clock = clock or time.monotonic
        self.emit = emit or (lambda *args, **kwargs: None)
        self.cache, self.pending = {}, []
        self.active, self.editor = None, None
        self.signature, self.sources_signature = None, None
        self.generation = self.display_revision = 0
        self.present, self.helper = False, None
        self.last_snapshot_error = None
        self.refresh_signature()
        self.next_signature_check = self.clock() + 1.0

    def locate(self):
        choices = ([self.helper_override] if self.helper_override else
                   [self.roots[0] / "ChatGPT-TitleSync.Rules.exe",
                    self.roots[1] / "shared" / "windows" / "ChatGPT-TitleSync.Rules.exe"])
        return next((p for p in choices if p and p.is_file()), None)

    def refresh_signature(self):
        helper = self.locate()
        try:
            hs = helper.stat() if helper else None
            helper_sig = (str(helper), hs.st_size, hs.st_mtime_ns) if hs else None
        except OSError:
            helper, helper_sig = None, None
        try:
            st = self.rules_path.stat()
            self.present = True
            if st.st_size > MAX_BYTES:
                rules_sig = ("oversized", st.st_size, st.st_mtime_ns)
            else:
                data = self.rules_path.read_bytes()
                if len(data) > MAX_BYTES:
                    rules_sig = ("oversized", len(data), st.st_mtime_ns)
                else:
                    rules_sig = ("data", hashlib.sha256(data).digest())
        except FileNotFoundError:
            self.present, rules_sig = False, ("absent",)
        except OSError:
            self.present, rules_sig = True, ("unreadable",)
        signature = (rules_sig, helper_sig)
        self.helper = helper
        if signature != self.signature:
            self.signature = signature
            self.generation += 1
            self.display_revision += 1
            self.cache.clear()
            self.pending.clear()
            self._abandon()
            return True
        return False

    def default_display(self, raw):
        return raw + SUFFIX if self.caption_mode else raw

    def display(self, raw):
        if not self.present:
            return self.default_display(raw)
        item = self.cache.get(raw)
        if item is not None:
            return item["display"]
        if len(self.cache) >= MAX_ENTRIES:
            return self.default_display(raw)
        self.cache[raw] = {"display": self.default_display(raw), "complete": False}
        if self.helper is None:
            self._complete(raw, self.default_display(raw), "companion_missing", self.generation)
        else:
            self.pending.append((raw, self.generation))
        return self.default_display(raw)

    def _complete(self, raw, display, code, generation):
        if generation != self.generation or raw not in self.cache:
            return
        self.cache[raw] = {"display": display, "complete": True, "code": code}
        self.display_revision += 1
        if code:
            self.emit("name_replacement_fallback", Code=code)

    def _abandon(self):
        if self.active is not None:
            self.active["abandoned"] = True
            if self.active["process"].poll() is None:
                try:
                    self.active["process"].kill()  # exact Popen-owned child only
                except OSError:
                    self.emit("name_replacement_fallback", Code="owned_worker_cancel_failed")

    def _cleanup(self, worker):
        for path in worker["paths"]:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass

    def pump(self):
        """Never wait for regex, UI, a source read, or a child process here."""
        changed = False
        if self.clock() >= self.next_signature_check:
            self.next_signature_check = self.clock() + 1.0
            changed = self.refresh_signature()
        worker = self.active
        if worker is not None:
            code = worker["process"].poll()
            if code is None:
                if not worker["abandoned"] and self.clock() - worker["started"] >= 1.5:
                    self._complete(worker["raw"], self.default_display(worker["raw"]), "worker_timeout", worker["generation"])
                    self._abandon()
                return changed
            self.active = None
            if not worker["abandoned"]:
                raw, generation = worker["raw"], worker["generation"]
                display, failure = self.default_display(raw), "worker_io"
                try:
                    output, status = worker["output"], worker["status"]
                    if output.stat().st_size > (MAX_UNITS + (10 if self.caption_mode else 0)) * 2 or status.stat().st_size > 256:
                        raise ValueError("oversized result")
                    data = output.read_bytes()
                    if len(data) % 2:
                        raise ValueError("odd UTF-16 output")
                    result = data.decode("utf-16-le")
                    tag = status.read_bytes().decode("ascii").strip()
                    if code == 0 and tag == "ok":
                        if not result.strip() or result.strip().casefold() == "chatgpt" or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in result):
                            raise ValueError("invalid display")
                        display, failure = result, None
                    elif (code == 2 and tag.startswith("fallback:") and
                          (result == raw or (self.caption_mode and result == raw + SUFFIX))):
                        display = result
                        failure = tag.split(":", 1)[1] or "unspecified"
                except (OSError, ValueError, UnicodeError):
                    pass
                self._complete(raw, display, failure, generation)
            self._cleanup(worker)
            changed = True
        while self.active is None and self.pending:
            raw, generation = self.pending.pop(0)
            if generation != self.generation:
                continue
            paths = []
            try:
                folder = self.runtime / "name-rule-work"
                folder.mkdir(parents=True, exist_ok=True)
                stem = str(os.getpid()) + "-" + uuid.uuid4().hex
                inp, output, status = [folder / (stem + suffix) for suffix in (".in", ".out", ".status")]
                paths = [inp, output, status]
                inp.write_bytes(raw.encode("utf-16-le"))
                if self.helper is None:
                    raise FileNotFoundError("companion missing")
                argv = [str(self.helper), "--format"] + (["--caption"] if self.caption_mode else []) + [
                        "--rules", str(self.rules_path), "--input", str(inp),
                        "--output", str(output), "--status", str(status)]
                process = self.launch(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                      creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                self.active = {"process": process, "raw": raw, "generation": generation,
                               "started": self.clock(), "output": output, "status": status,
                               "paths": paths, "abandoned": False}
            except (OSError, ValueError, UnicodeError):
                for path in paths:
                    path.unlink(missing_ok=True)
                self._complete(raw, self.default_display(raw), "worker_start_failed", generation)
                changed = True
        return changed

    def update_sources(self, known):
        rows = sorted((str(ident), item.get("Title", "")) for ident, item in known.items())
        signature = tuple(rows)
        if signature == self.sources_signature:
            return
        try:
            data = encode_sources(raw for _, raw in rows)
            atomic_bytes(self.sources_path, data)
            self.sources_signature = signature
            self.last_snapshot_error = None
        except (OSError, ValueError, UnicodeError) as error:
            code = type(error).__name__
            if code != self.last_snapshot_error:
                self.emit("name_replacement_fallback", Code="source_snapshot_" + code)
                self.last_snapshot_error = code

    def open_editor(self):
        helper = self.locate()
        if helper is None:
            raise FileNotFoundError("ChatGPT-TitleSync.Rules.exe is required for Name replacement.")
        if self.editor is not None and self.editor.poll() is None:
            return
        help_file = next((p for base in self.roots for p in (base / "docs" / "name-replacement.html",)
                          if p.is_file()), self.roots[1] / "docs" / "name-replacement.html")
        self.editor = self.launch([str(helper), "--edit", "--rules", str(self.rules_path),
                                  "--sources", str(self.sources_path), "--help", str(help_file.resolve())],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def close(self):
        self._abandon()
        if self.active and self.active["process"].poll() is not None:
            self._cleanup(self.active)
            self.active = None