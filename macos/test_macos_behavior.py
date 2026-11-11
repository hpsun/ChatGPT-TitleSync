"""Behavior simulation only. No native macOS calls, build, timing or pixel assertions."""
import json
from pathlib import Path
import unittest
from macos_mock_backend import Backend, Engine, Window, AXNode, mock_document_title

class BehaviorTests(unittest.TestCase):
    def test_permission_not_granted(self):
        w=Window(); b=Backend([w], trusted=False)
        self.assertEqual(Engine().scan(b)[0]["status"], "permission_missing")
        self.assertEqual(b.writes, []); self.assertEqual(w.caption, "ChatGPT")
    def test_readonly_ax_title_is_not_success(self):
        w=Window(writable=False); b=Backend([w])
        row=Engine().scan(b)[0]
        self.assertEqual(row["status"], "readonly"); self.assertFalse(row["success"])
        self.assertEqual(row["name"], "会话甲"); self.assertEqual(b.writes, [])
    def test_conversation_switch_preserves_original(self):
        w=Window(); b=Backend([w]); e=Engine()
        e.scan(b); w.conversation="会话乙"; e.scan(b)
        self.assertEqual(w.caption, "会话乙 — ChatGPT")
        self.assertEqual(e.disable(b), ["restored"]); self.assertEqual(w.caption, "ChatGPT")
    def test_multiple_windows_independent(self):
        a=Window(); z=Window(token="window-B", conversation="会话乙")
        b=Backend([a,z]); e=Engine(); e.scan(b)
        self.assertEqual([a.caption,z.caption], ["会话甲 — ChatGPT","会话乙 — ChatGPT"])
        e.disable(b); self.assertEqual([a.caption,z.caption], ["ChatGPT","ChatGPT"])
    def test_pid_start_or_window_identity_change_not_reused(self):
        for replacement in [Window(pid=101,caption="new"), Window(launched="boot-B",caption="new"),
                            Window(token="window-B",caption="new")]:
            with self.subTest(identity=replacement.identity):
                w=Window(); b=Backend([w]); e=Engine(); e.scan(b)
                b.windows=[replacement]
                self.assertEqual(e.disable(b), ["restore_skipped_identity"])
                self.assertEqual(replacement.caption, "new")
    def test_disable_restores_owned_caption(self):
        w=Window(caption="original"); b=Backend([w]); e=Engine(); e.scan(b)
        self.assertEqual(e.disable(b), ["restored"]); self.assertEqual(w.caption,"original")
    def test_external_rename_not_overwritten_on_disable(self):
        w=Window(); b=Backend([w]); e=Engine(); e.scan(b); w.caption="external owner"
        self.assertEqual(e.disable(b), ["restore_skipped_external_change"])
        self.assertEqual(w.caption,"external owner")
    def test_source_unreadable_does_not_claim_success(self):
        w=Window(conversation=None); b=Backend([w]); rows=Engine().scan(b)
        self.assertFalse(rows[0]["success"]); self.assertEqual(b.writes,[])
    def test_write_error_not_success(self):
        w=Window(write_error=True); b=Backend([w]); e=Engine()
        self.assertFalse(e.scan(b)[0]["success"]); self.assertEqual(e.owned,{})
    def test_write_readback_mismatch_not_success(self):
        w=Window(readback_mismatch=True); b=Backend([w]); e=Engine()
        self.assertEqual(e.scan(b)[0]["status"],"write_readback_failed")
        self.assertEqual(e.owned,{})
    def test_document_is_leaf_body_never_read(self):
        doc=AXNode("AXWebArea",title="会话甲",forbid_children=True)
        window=AXNode("AXWindow",children=[AXNode("AXGroup",children=[doc])])
        self.assertEqual(mock_document_title(window),"会话甲")
    def test_ambiguous_documents_rejected(self):
        window=AXNode("AXWindow",children=[AXNode("AXWebArea",title="甲"),AXNode("AXWebArea",title="乙")])
        with self.assertRaises(ValueError): mock_document_title(window)
    def test_generic_document_title_rejected(self):
        with self.assertRaises(ValueError): mock_document_title(AXNode("AXWebArea",title="ChatGPT"))

if __name__ == "__main__":
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(BehaviorTests)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    report={"kind":"MOCK BEHAVIOR SIMULATION ONLY","testsRun":result.testsRun,
            "failures":len(result.failures),"errors":len(result.errors),
            "success":result.wasSuccessful(),
            "nativeMacCompiled":False,"realAXCallsVerified":False,"realMacPixelsVerified":False,
            "cases":unittest.defaultTestLoader.getTestCaseNames(BehaviorTests)}
    Path(__file__).with_name("macos_mock_results.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)
