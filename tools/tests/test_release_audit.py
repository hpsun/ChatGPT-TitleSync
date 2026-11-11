"""Synthetic package-boundary tests; no app, SDK, or user evidence is read."""
import hashlib, importlib.util, json, shutil, subprocess, tempfile, unittest, zipfile
from pathlib import Path
spec=importlib.util.spec_from_file_location("release_audit",Path(__file__).resolve().parents[1]/"release_audit.py")
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
class ReleaseAuditTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix="chatgpt-titlesync-audit-test-");self.root=Path(self.temp.name)
  (self.root/"README.md").write_text("# Fixture\n\n[Source](sample.py)\n",encoding="utf-8")
  (self.root/"sample.py").write_text("interval = 1\n",encoding="utf-8")
  (self.root/"LICENSE").write_text("MIT License\nPermission is hereby granted, free of charge\n",encoding="utf-8")
  self.policy={"allow":["README.md","sample.py","LICENSE","source-sha256.txt"],"required":["README.md","sample.py","LICENSE"],"source_rules":[{"name":"one-second","path":"sample.py","pattern":r"interval = 1\b"}]}
 def tearDown(self):self.temp.cleanup()
 def runaudit(self):return audit.audit(self.root,self.policy,True)
 def test_raw_byte_attributes_preserve_lf_and_crlf_with_autocrlf(self):
  if not shutil.which("git"):self.skipTest("Git unavailable")
  (self.root/".gitattributes").write_bytes(b"* -text\n")
  samples={"sample.py":b"interval = 1\r\n# CRLF\r\n","other.cs":b"// LF\nclass Fixture {}\n"}
  for name,data in samples.items():(self.root/name).write_bytes(data)
  def git(*args):
   return subprocess.run(["git","-C",str(self.root),"-c","core.autocrlf=true",*args],capture_output=True,check=True).stdout
  git("init","-q");git("add",".gitattributes",*samples)
  for name,data in samples.items():self.assertEqual(git("show",":"+name),data)
  out=self.root/"checkout";out.mkdir()
  git("checkout-index","-a","--prefix="+out.as_posix()+"/")
  for name,data in samples.items():self.assertEqual((out/name).read_bytes(),data)
 def test_allowlist_excludes_local_artifacts(self):
  for name in ["validation/private.json","logs/runtime.jsonl","runtime/sdk.exe","sample.exe"]:
   p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text("synthetic",encoding="utf-8")
  r=self.runaudit();self.assertTrue(r["passed"],r["errors"]);self.assertEqual(set(r["files"]),{"README.md","LICENSE","sample.py"})
 def test_private_document_link_is_rejected(self):
  p=self.root/"validation/private.json";p.parent.mkdir();p.write_text("{}")
  (self.root/"README.md").write_text("[Private](validation/private.json)",encoding="utf-8")
  self.assertTrue(any("link-not-in-source-package" in x for x in self.runaudit()["errors"]))
 def test_default_change_fails(self):
  (self.root/"sample.py").write_text("interval = 5\n",encoding="utf-8")
  self.assertIn("source-policy:one-second",self.runaudit()["errors"])
 def test_private_path_is_rejected_without_echoing_it(self):
  value="C:"+chr(92)+"Users"+chr(92)+"SyntheticUser"+chr(92)+"private"
  (self.root/"sample.py").write_text("interval = 1\npath="+repr(value),encoding="utf-8")
  # Source escaped backslashes may be doubled; the scanner still identifies the path.
  self.assertTrue(any("personal-absolute-path" in x for x in self.runaudit()["errors"]))
 def test_token_shape_is_rejected(self):
  value="ghp_"+"x"*36
  (self.root/"sample.py").write_text("interval = 1\ntoken="+repr(value),encoding="utf-8")
  r=self.runaudit();self.assertTrue(any("credential-like-token" in x for x in r["errors"]));self.assertNotIn(value,str(r["errors"]))
 def test_stale_manifest_is_rejected(self):
  (self.root/"source-sha256.txt").write_text("0"*64+"  sample.py\n")
  self.assertIn("source-manifest-stale:sample.py",self.runaudit()["errors"])
 def test_missing_anchor_is_rejected(self):
  (self.root/"README.md").write_text("[Missing](README.md#absent)")
  self.assertTrue(any("missing-link-anchor" in x for x in self.runaudit()["errors"]))
 def test_markdown_embedded_html_heading_anchor(self):
  (self.root/"README.md").write_text('<h2 id="section">Fixture</h2>\n[Section](#section)\n',encoding="utf-8")
  r=self.runaudit();self.assertTrue(r["passed"],r["errors"])
 def test_pending_protocol_is_a_blocking_gate(self):
  self.policy["final_protocol_acceptance"]="pending"
  self.assertIn("final-three-layer-protocol-acceptance-pending",self.runaudit()["errors"])
 def test_zip_manifest_matches_every_source_byte(self):
  r=self.runaudit();self.assertTrue(r["passed"]);out=self.root/"out"
  p=audit.make_package(self.root,r["files"],out)
  with zipfile.ZipFile(p["file"]) as z:
   entries=z.namelist();self.assertTrue(all(n.startswith("ChatGPT-TitleSync-source/") for n in entries))
   lines=z.read("ChatGPT-TitleSync-source/SHA256SUMS.txt").decode().splitlines()
   for line in lines:
    expected,name=line.split("  ",1);self.assertEqual(expected,hashlib.sha256(z.read("ChatGPT-TitleSync-source/"+name)).hexdigest())
   self.assertFalse(any("validation/" in n or n.endswith(".exe") for n in entries))
 @unittest.skipUnless(shutil.which("git"),"git not installed")
 def test_forced_private_tracked_file_is_rejected(self):
  subprocess.run(["git","init","-q",str(self.root)],check=True)
  p=self.root/"logs"/"private.json";p.parent.mkdir();p.write_text("{}")
  subprocess.run(["git","-C",str(self.root),"add","-f","logs/private.json"],check=True)
  self.assertIn("forbidden-or-unreviewed-tracked-file:logs/private.json",self.runaudit()["errors"])
 def icon_fixture(self, choice="45", digest_key="icon_sha256"):
  assets=self.root/"assets";assets.mkdir()
  icon=b"synthetic-reviewed-image";(assets/"baseline.png").write_bytes(icon)
  (assets/"icon-selected.json").write_text(json.dumps({"Choice":choice}),encoding="utf-8")
  self.policy["allow"].extend(["assets/baseline.png","assets/icon-selected.json"])
  self.policy[digest_key]={"assets/baseline.png":hashlib.sha256(icon).hexdigest()}
 def test_selected_icon_hash_is_enforced(self):
  self.icon_fixture();self.policy["selected_icon"]="45"
  self.assertTrue(self.runaudit()["passed"])
  (self.root/"assets/baseline.png").write_bytes(b"unexpected-artwork")
  self.assertIn("selected-icon-asset-baseline-mismatch:assets/baseline.png",self.runaudit()["errors"])
 def test_selected_icon_metadata_must_match_policy(self):
  self.icon_fixture("46");self.policy["selected_icon"]="45"
  self.assertIn("selected-icon-mismatch",self.runaudit()["errors"])
 def test_legacy_a1_policy_remains_readable(self):
  self.icon_fixture("A1","a1_sha256")
  self.assertTrue(self.runaudit()["passed"])
if __name__=="__main__":unittest.main()
