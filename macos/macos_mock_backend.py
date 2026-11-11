"""Deterministic macOS behavior model. This does NOT invoke Cocoa/AX or emulate macOS."""
from dataclasses import dataclass, field

@dataclass
class Window:
    pid: int = 100
    launched: str = "boot-A"
    token: str = "window-A"
    caption: str = "ChatGPT"
    conversation: str | None = "会话甲"
    writable: bool = True
    write_error: bool = False
    readback_mismatch: bool = False
    @property
    def identity(self):
        return self.pid, self.launched, self.token

class Backend:
    def __init__(self, windows=(), trusted=True):
        self.windows = list(windows)
        self.trusted = trusted
        self.writes = []
    def set_title(self, window, value):
        self.writes.append((window.identity, value))
        if window.write_error:
            return False
        window.caption = "provider rejected readback" if window.readback_mismatch else value
        return True

class Engine:
    """Specification model, not a binding shared with native implementation."""
    def __init__(self):
        self.owned = {}
    def scan(self, backend):
        if not backend.trusted:
            return [{"status": "permission_missing", "success": False}]
        live = {window.identity for window in backend.windows}
        self.owned = {key: value for key, value in self.owned.items() if key in live}
        rows = []
        for window in backend.windows:
            name = window.conversation
            if not name or not name.strip() or name == "ChatGPT":
                rows.append({"status": "source_unavailable", "success": False})
                continue
            if not window.writable:
                rows.append({"status": "readonly", "name": name, "success": False})
                continue
            wanted = name + " — ChatGPT"
            old = self.owned.get(window.identity)
            if window.caption != wanted:
                if old and window.caption != old["last"]:
                    old = None
                original = old["original"] if old else window.caption
                if not backend.set_title(window, wanted) or window.caption != wanted:
                    rows.append({"status": "write_readback_failed", "name": name, "success": False})
                    continue
                self.owned[window.identity] = {"original": original, "last": wanted}
            rows.append({"status": "confirmed", "name": name, "success": True})
        return rows
    def disable(self, backend):
        results = []
        current = {window.identity: window for window in backend.windows}
        for identity, record in list(self.owned.items()):
            window = current.get(identity)
            if window is None:
                results.append("restore_skipped_identity")
            elif window.caption != record["last"]:
                results.append("restore_skipped_external_change")
            elif not window.writable or not backend.set_title(window, record["original"]) or window.caption != record["original"]:
                results.append("restore_failed")
            else:
                results.append("restored")
                del self.owned[identity]
        return results

@dataclass
class AXNode:
    role: str
    title: str = ""
    children: list = field(default_factory=list)
    forbid_children: bool = False

def mock_document_title(window):
    queue = [(window, 0)]
    documents = []
    visited = 0
    while queue:
        node, depth = queue.pop(0)
        visited += 1
        if visited > 64:
            raise ValueError("native envelope limit")
        if node.role == "AXWebArea":
            documents.append(node)
            continue  # NEVER request AXWebArea children/body
        if node.role in {"AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea"}:
            if depth >= 8 or node.forbid_children:
                raise ValueError("native envelope unreadable")
            queue.extend((child, depth + 1) for child in node.children)
    if len(documents) != 1 or not documents[0].title.strip() or documents[0].title == "ChatGPT":
        raise ValueError("unavailable or ambiguous")
    return documents[0].title
