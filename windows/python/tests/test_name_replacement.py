"""Owned-file/process tests; no ChatGPT, UI, registry or monitor entry is used."""
import ast
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cts_name_rules", ROOT / "name_replacement.py")
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)

FIXTURE = r'''
import json,sys,time
from pathlib import Path
assert sys.argv[1] == "--format"
values=sys.argv[2:]
caption_mode="--caption" in values
if caption_mode: values.remove("--caption")
args=dict(zip(values[0::2],values[1::2]))
cfg=json.loads(Path(args["--rules"]).read_text())
raw=Path(args["--input"]).read_bytes().decode("utf-16-le")
if cfg.get("hang"): time.sleep(30)
value=cfg.get("value",raw)
if cfg.get("raw"): value=raw
if caption_mode and cfg.get("append_chatgpt_suffix",True): value+=" — ChatGPT"
Path(args["--output"]).write_bytes(b"x" if cfg.get("odd") else value.encode("utf-16-le"))
Path(args["--status"]).write_text(cfg.get("status","ok"),encoding="ascii")
raise SystemExit(cfg.get("exit",0))
'''


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="cts-rules-owned-")
        self.root=Path(self.temp.name)
        self.config=self.root/"title-rules.json"
        self.helper=self.root/"fake-helper.exe"
        self.helper.write_bytes(b"owned fixture marker")
        self.fixture=self.root/"fixture.py"
        self.fixture.write_text(FIXTURE,encoding="utf-8")
        self.events,self.commands,self.children=[],[],[]
        self.controllers=[]
    def tearDown(self):
        for c in self.controllers:c.close()
        for p in self.children:
            if p.poll() is None:p.kill()
            p.wait(timeout=3)
        self.temp.cleanup()
    def controller(self, **kwargs):
        def launch(argv,**options):
            self.commands.append(argv)
            p=subprocess.Popen([sys.executable,str(self.fixture)]+argv[1:],**options)
            self.children.append(p)
            return p
        c=rules.NameReplacement(self.root/"profile/settings.json",lambda *a,**kw:self.events.append((a,kw)),
                                rules_path=self.config,helper=self.helper,launch=launch,**kwargs)
        self.controllers.append(c)
        return c
    def save(self, **cfg):self.config.write_text(json.dumps(cfg),encoding="utf-8")
    def finish(self,c,raw):
        c.display(raw)
        until=time.monotonic()+4
        while time.monotonic()<until:
            c.pump()
            if c.cache.get(raw,{}).get("complete"):return c.display(raw)
            time.sleep(.01)
        self.fail("owned format fixture did not complete")
    def test_absent_rules_are_identity_without_creating_config_or_worker(self):
        c=self.controller();self.assertEqual(c.display("示例😀"),"示例😀")
        for _ in range(3):c.pump()
        self.assertFalse(self.config.exists());self.assertFalse(self.commands)
    def test_cts1_utf16_lengths_and_no_suffix(self):
        packet=rules.encode_sources(["示例😀","Second"])
        self.assertEqual(packet[:4],b"CTS1");self.assertEqual(struct.unpack_from("<I",packet,4)[0],2)
        self.assertEqual(struct.unpack_from("<I",packet,8)[0],4)
        self.assertEqual(packet[12:20].decode("utf-16-le"),"示例😀")
        self.assertNotIn(" — ChatGPT".encode("utf-16-le"),packet)
    def test_snapshot_only_rewrites_on_name_or_window_set_change(self):
        c=self.controller();known={"id1":{"Title":"Raw"}}
        with mock.patch.object(rules,"atomic_bytes") as write:
            c.update_sources(known);c.update_sources(known)
            self.assertEqual(write.call_count,1)
            c.update_sources({"id2":{"Title":"Raw"}})
            self.assertEqual(write.call_count,2)
    def test_snapshot_bounds(self):
        b=rules.encode_sources(["x"*512]*1000)
        self.assertLessEqual(len(b),131072);self.assertLessEqual(struct.unpack_from("<I",b,4)[0],128)
    def test_unicode_format_contract_paths_only_argv(self):
        self.save(value="结果😀")
        c=self.controller();raw="原始 :: 示例😀"
        self.assertEqual(self.finish(c,raw),"结果😀")
        self.assertNotIn(raw,self.commands[0])
        self.assertEqual(self.commands[0][1],"--format")
        self.assertEqual(c.cache[raw]["code"],None)
    def test_complete_fallback_is_cached_not_retried(self):
        self.save(raw=True,status="fallback:invalid_rule",exit=2)
        c=self.controller();self.assertEqual(self.finish(c,"Original"),"Original")
        for _ in range(8):c.pump();c.display("Original")
        self.assertEqual(len(self.commands),1);self.assertEqual(len(self.events),1)
        self.assertEqual(c.cache["Original"]["code"],"invalid_rule")
    def test_missing_companion_fallback_logged_once(self):
        self.helper.unlink();self.save(value="New")
        clock=[0.0];c=self.controller(clock=lambda:clock[0])
        for _ in range(5):self.assertEqual(c.display("Raw"),"Raw");c.pump()
        self.assertFalse(self.commands);self.assertEqual(len(self.events),1)
        original_rules=self.config.read_bytes();generation=c.generation
        self.helper.write_bytes(b"restored owned fixture marker")
        clock[0]=1.01;c.pump()
        self.assertGreater(c.generation,generation)
        self.assertEqual(self.finish(c,"Raw"),"New")
        self.assertEqual(self.config.read_bytes(),original_rules)
        self.assertEqual(len(self.commands),1)
    def test_malformed_or_unsafe_success_output_is_never_committed(self):
        for index,cfg in enumerate(({"odd":True},{"value":""},{"value":"ChatGPT"},{"value":"bad\nname"},{"value":"x"*513})):
            self.save(**cfg);c=self.controller();raw="Raw"+str(index)
            self.assertEqual(self.finish(c,raw),raw)
            self.assertEqual(c.cache[raw]["code"],"worker_io")
    def test_fallback_exit_cannot_return_partial_transformation(self):
        self.save(value="Partial",status="fallback:invalid_rule",exit=2)
        c=self.controller();self.assertEqual(self.finish(c,"Raw"),"Raw")
    def test_same_size_rule_change_within_second_invalidates_cache(self):
        self.save(value="One");c=self.controller();self.assertEqual(self.finish(c,"Raw"),"One")
        old=c.generation;self.save(value="Two");c.refresh_signature();c.pump()
        self.assertGreater(c.generation,old);self.assertEqual(self.finish(c,"Raw"),"Two")
    def test_1500ms_deadline_only_cancels_owned_worker_and_caches_raw(self):
        self.save(hang=True);clock=[0.0];c=self.controller(clock=lambda:clock[0])
        c.display("Raw");c.pump();self.assertEqual(len(self.children),1)
        clock[0]=1.51;started=time.monotonic();c.pump()
        self.assertLess(time.monotonic()-started,.2)
        self.assertEqual(c.display("Raw"),"Raw");self.assertEqual(c.cache["Raw"]["code"],"worker_timeout")
        self.children[0].wait(timeout=3);c.pump();c.display("Raw");c.pump()
        self.assertEqual(len(self.children),1)
    def test_rule_generation_change_discards_old_async_result(self):
        self.save(hang=True);c=self.controller();c.display("Raw");c.pump()
        self.save(value="Fresh");c.refresh_signature();c.pump()
        self.assertEqual(self.finish(c,"Raw"),"Fresh")
        self.assertEqual(len(self.children),2)

    def test_caption_absent_config_adds_default_suffix_without_worker(self):
        c=self.controller(caption_mode=True)
        self.assertEqual(c.display("示例😀"),"示例😀 — ChatGPT")
        self.assertFalse(self.config.exists());self.assertFalse(self.commands)
    def test_caption_worker_returns_complete_title_without_double_suffix(self):
        self.save(value="Display")
        c=self.controller(caption_mode=True)
        self.assertEqual(self.finish(c,"Raw"),"Display — ChatGPT")
        self.assertIn("--caption",self.commands[0])
        self.assertNotIn("Raw",self.commands[0])
    def test_caption_empty_disabled_rules_can_disable_suffix(self):
        self.save(enabled=False,rules=[],append_chatgpt_suffix=False)
        c=self.controller(caption_mode=True)
        self.assertEqual(self.finish(c,"原始😀"),"原始😀")
        self.assertEqual(len(self.commands),1)
    def test_caption_suffix_toggle_invalidates_display_only(self):
        self.save(value="Display",append_chatgpt_suffix=False)
        c=self.controller(caption_mode=True)
        self.assertEqual(self.finish(c,"Raw"),"Display")
        generation=c.generation
        self.save(value="Display",append_chatgpt_suffix=True);c.refresh_signature()
        self.assertGreater(c.generation,generation)
        self.assertEqual(self.finish(c,"Raw"),"Display — ChatGPT")
    def test_caption_handled_fallback_accepts_only_complete_raw_forms(self):
        for append in (False,True):
            self.save(raw=True,status="fallback:invalid_rule",exit=2,append_chatgpt_suffix=append)
            c=self.controller(caption_mode=True)
            self.assertEqual(self.finish(c,"Original"),"Original"+(" — ChatGPT" if append else ""))
        self.save(value="Partial",status="fallback:invalid_rule",exit=2,append_chatgpt_suffix=False)
        c=self.controller(caption_mode=True)
        self.assertEqual(self.finish(c,"Original"),"Original — ChatGPT")
        self.assertEqual(c.cache["Original"]["code"],"worker_io")
    def test_caption_full_output_limit_is_522_utf16_units(self):
        self.save(value="x"*512)
        c=self.controller(caption_mode=True)
        self.assertEqual(self.finish(c,"Raw"),"x"*512+" — ChatGPT")
        self.save(value="x"*513);c.refresh_signature()
        self.assertEqual(self.finish(c,"Raw"),"Raw — ChatGPT")
        self.assertEqual(c.cache["Raw"]["code"],"worker_io")
    def test_caption_missing_helper_default_suffix_then_same_raw_recovery(self):
        self.helper.unlink();self.save(append_chatgpt_suffix=False)
        clock=[0.0];c=self.controller(caption_mode=True,clock=lambda:clock[0])
        self.assertEqual(c.display("Raw"),"Raw — ChatGPT")
        original=self.config.read_bytes()
        self.helper.write_bytes(b"restored caption fixture");clock[0]=1.01;c.pump()
        self.assertEqual(self.finish(c,"Raw"),"Raw")
        self.assertEqual(self.config.read_bytes(),original)
    def test_caption_timeout_retains_default_suffix_and_cached_fallback(self):
        self.save(hang=True,append_chatgpt_suffix=False);clock=[0.0]
        c=self.controller(caption_mode=True,clock=lambda:clock[0])
        c.display("Raw");c.pump();clock[0]=1.51;c.pump()
        self.assertEqual(c.display("Raw"),"Raw — ChatGPT")
        self.assertEqual(c.cache["Raw"]["code"],"worker_timeout")
        self.children[-1].wait(timeout=3);c.pump();c.display("Raw");c.pump()
        self.assertEqual(len(self.commands),1)



class OwnershipTests(unittest.TestCase):
    def namespace(self):
        tree=ast.parse((ROOT/"chatgpt_window_titles.py").read_text(encoding="utf-8-sig"))
        node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=="refresh_owned_displays")
        info={"Hwnd":7,"Pid":1};captions={7:"Raw — ChatGPT"};writes=[]
        def put(i,text):captions[i["Hwnd"]]=text;writes.append(text)
        ns={"key":lambda i:(i["Hwnd"],i["Pid"]) if i else None,"identity":lambda h:info,
            "caption":lambda h:captions[h],"set_caption":put}
        exec(compile(ast.Module(body=[node],type_ignores=[]),str(ROOT),"exec"),ns)
        return ns,info,captions,writes
    def test_display_only_refresh_preserves_raw_and_original_lease(self):
        ns,info,captions,writes=self.namespace();ident=(7,1)
        record={"Identity":info,"Original":"Native original","Last":captions[7]}
        known={ident:{"Identity":info,"Title":"Raw"}}
        ns["refresh_owned_displays"](known,{ident:record},lambda *a,**k:None,types.SimpleNamespace(display=lambda raw:"Display — ChatGPT"))
        self.assertEqual(writes,["Display — ChatGPT"]);self.assertEqual(record["Original"],"Native original")
        self.assertEqual(known[ident]["Title"],"Raw")
    def test_full_caption_refresh_can_omit_suffix_and_preserves_raw_lease(self):
        ns,info,captions,writes=self.namespace();ident=(7,1)
        record={"Identity":info,"Original":"Native original","Last":captions[7]}
        known={ident:{"Identity":info,"Title":"Raw"}}
        ns["refresh_owned_displays"](known,{ident:record},lambda *a,**k:None,types.SimpleNamespace(display=lambda raw:"Display"))
        self.assertEqual(writes,["Display"]);self.assertEqual(record["Original"],"Native original")
        self.assertEqual(known[ident]["Title"],"Raw")
    def test_display_refresh_never_claims_manual_or_generic_caption(self):
        for current in ("User manual title","ChatGPT"):
            ns,info,captions,writes=self.namespace();captions[7]=current
            record={"Identity":info,"Original":"Native original","Last":"Raw — ChatGPT"}
            ns["refresh_owned_displays"]({(7,1):{"Title":"Raw"}},{(7,1):record},lambda *a,**k:None,types.SimpleNamespace(display=lambda r:"Display"))
            self.assertFalse(writes);self.assertEqual(record["Original"],"Native original")


if __name__=="__main__":unittest.main()