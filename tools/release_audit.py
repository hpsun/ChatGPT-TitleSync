#!/usr/bin/env python3
"""Offline, allowlisted source-package audit. No network, publish, or app access."""
from __future__ import annotations
import argparse, fnmatch, hashlib, json, os, re, subprocess, sys, unicodedata, zipfile
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

FORBIDDEN_DIRS = {".git", "validation", "logs", "snapshots", "snapshot", "runtime", "runtimes",
                 "target", "bin", "obj", "__pycache__", "node_modules", ".venv", "venv", ".local"}
FORBIDDEN_EXT = {".exe", ".dll", ".pdb", ".obj", ".o", ".a", ".lib", ".res", ".syso", ".zip",
                 ".7z", ".jsonl", ".log", ".tmp", ".bak", ".bin", ".dylib", ".so", ".pyc"}
PRIVATE_TEXT = [
    ("personal-absolute-path", re.compile(r"(?i)\b[a-z]:[/\\]+(?:users|trading|working\d*)[/\\]+")),
    ("credential-like-token", re.compile(r"(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{24,})")),
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
]
TEXT_EXT = {".md", ".html", ".json", ".txt", ".py", ".ps1", ".cs", ".rs", ".go", ".mod", ".toml", ".lock", ".yml", ".yaml", ".ahk", ".swift", ".m", ".h", ".sh", ".applescript"}
class AuditFailure(Exception): pass

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def safe_name(name: str) -> bool:
    p = Path(name.replace("\\", "/"))
    return not p.is_absolute() and ".." not in p.parts and not any(x.lower() in FORBIDDEN_DIRS for x in p.parts) and p.suffix.lower() not in FORBIDDEN_EXT

def allowed(name: str, policy: dict) -> bool:
    name = name.replace("\\", "/")
    if not safe_name(name): return False
    return any(fnmatch.fnmatchcase(name, p) for p in policy["allow"])

def own_git(root: Path):
    try:
        p = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10)
        if p.returncode or Path(p.stdout.strip()).resolve() != root.resolve(): return None
        q = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, timeout=10, check=True)
        return [x.decode("utf-8") for x in q.stdout.split(b"\0") if x]
    except (OSError, subprocess.SubprocessError): return None

def inventory(root: Path, policy: dict) -> list[str]:
    names=[]
    for folder, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if d.lower() not in FORBIDDEN_DIRS and not (Path(folder)/d).is_symlink()]
        for name in files:
            p=Path(folder)/name
            rel=p.relative_to(root).as_posix()
            if allowed(rel, policy): names.append(rel)
    return sorted(names)

class HtmlInfo(HTMLParser):
    def __init__(self):
        super().__init__(); self.links=[]; self.anchors=set()
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if "id" in a: self.anchors.add(a["id"])
        if tag=="a" and "name" in a: self.anchors.add(a["name"])
        if tag in ("a","img"):
            key="href" if tag=="a" else "src"
            if key in a: self.links.append(a[key])

def md_info(text: str):
    # Ignore fenced examples before interpreting links/headings.
    clean=re.sub(r"(?ms)^\s*```.*?^\s*```\s*$", "", text)
    links=[m.group(1).strip().split(' "')[0].strip("<>") for m in re.finditer(r"!?\[[^\]]*\]\(([^\n]+?)\)", clean)]
    parser=HtmlInfo();parser.feed(clean);anchors=parser.anchors;links.extend(parser.links)
    used={}
    for title in re.findall(r"(?m)^#{1,6}\s+(.+?)\s*#*\s*$", clean):
        slug=re.sub(r"[^\w\- ]", "", re.sub(r"<[^>]+>", "", title).lower(), flags=re.UNICODE).replace(" ", "-")
        slug=unicodedata.normalize("NFC", slug); n=used.get(slug,0);used[slug]=n+1
        anchors.add(slug if not n else slug+"-"+str(n))
    return links, anchors

def link_errors(root: Path, files: list[str]) -> list[str]:
    public=set(files); errors=[]; cache={}
    def info(name):
        if name not in cache:
            text=(root/name).read_text(encoding="utf-8-sig")
            if name.lower().endswith(".html"):
                p=HtmlInfo();p.feed(text);cache[name]=(p.links,p.anchors)
            else: cache[name]=md_info(text)
        return cache[name]
    for name in files:
        if not name.lower().endswith((".md",".html")): continue
        for href in info(name)[0]:
            u=urlsplit(href)
            if u.scheme:
                if u.scheme.lower() not in ("https","http","mailto"):errors.append("unsupported-link-scheme:"+name)
                continue
            if href.startswith("//"): continue
            try:
                target=(root/name).parent/unquote(u.path) if u.path else root/name
                target=target.resolve()
                rel=target.relative_to(root.resolve()).as_posix()
            except (ValueError,OSError): errors.append("link-outside-package:"+name);continue
            if rel not in public:errors.append("link-not-in-source-package:"+name+" -> "+rel);continue
            if u.fragment and rel.lower().endswith((".md",".html")) and unquote(u.fragment) not in info(rel)[1]:
                errors.append("missing-link-anchor:"+name+" -> "+rel+"#"+u.fragment)
    return errors

def audit(root: Path, policy: dict, force_allowlist=False) -> dict:
    root=root.resolve();errors=[]; tracked=own_git(root)
    if policy.get("final_protocol_acceptance")=="pending":errors.append("final-three-layer-protocol-acceptance-pending")
    if tracked is not None:
        for n in tracked:
            if not allowed(n, policy):errors.append("forbidden-or-unreviewed-tracked-file:"+n)
    mode="allowlist" if force_allowlist or tracked is None else "git-index"
    files=inventory(root,policy) if mode=="allowlist" else sorted(n for n in tracked if allowed(n,policy))
    public=set(files)
    for n in policy["required"]:
        if n not in public:errors.append("missing-required-public-file:"+n)
    folded=set()
    for n in files:
        if n.casefold() in folded:errors.append("case-colliding-path:"+n)
        folded.add(n.casefold());p=root/n
        try: p.resolve().relative_to(root)
        except ValueError:errors.append("symlink-outside-package:"+n);continue
        if p.is_symlink():errors.append("symlink-not-packaged:"+n);continue
        if not p.is_file():errors.append("missing-tracked-file:"+n);continue
        if p.suffix.lower() in TEXT_EXT or n in ("LICENSE",".gitignore",".gitattributes"):
            try:text=p.read_text(encoding="utf-8-sig")
            except UnicodeError:errors.append("non-utf8-public-text:"+n);continue
            for label,pat in PRIVATE_TEXT:
                if pat.search(text): errors.append(label+":"+n)
    if (root/"LICENSE").is_file():
        license_text=(root/"LICENSE").read_text(encoding="utf-8-sig")
        if not license_text.startswith("MIT License") or "Permission is hereby granted" not in license_text:
            errors.append("MIT-license-required")
    if tracked is not None and mode=="git-index":
        p=subprocess.run(["git","-C",str(root),"diff","--name-only","-z"],capture_output=True,timeout=10)
        dirty={x.decode("utf-8") for x in p.stdout.split(b"\0") if x}
        for n in sorted(dirty & public): errors.append("working-file-differs-from-staged-index:"+n)
    rules=[]
    for rule in policy.get("source_rules",[]):
        p=root/rule["path"]
        ok=p.is_file() and bool(re.search(rule["pattern"],p.read_text(encoding="utf-8-sig"),re.S|re.M))
        rules.append({"name":rule["name"],"path":rule["path"],"passed":ok})
        if not ok:errors.append("source-policy:"+rule["name"])
    for n,expected in policy.get("icon_sha256", policy.get("a1_sha256",{})).items():
        if n not in public or not (root/n).is_file() or digest((root/n).read_bytes())!=expected:
            errors.append("selected-icon-asset-baseline-mismatch:"+n)
    if "assets/icon-selected.json" in public:
        try:
            if json.loads((root/"assets/icon-selected.json").read_text(encoding="utf-8-sig")).get("Choice")!=policy.get("selected_icon", "A1"):
                errors.append("selected-icon-mismatch")
        except (ValueError,OSError):errors.append("invalid-icon-selection")
    if "source-sha256.txt" in public:
        for line in (root/"source-sha256.txt").read_text(encoding="utf-8-sig").splitlines():
            if not line.strip():continue
            m=re.fullmatch(r"([0-9a-fA-F]{64})\s+\*?(.+)",line)
            if not m:errors.append("invalid-source-manifest-line");continue
            n=m.group(2).replace("\\","/")
            if n not in public:errors.append("source-manifest-target-not-public:"+n)
            elif not (root/n).is_file() or digest((root/n).read_bytes())!=m.group(1).lower():
                errors.append("source-manifest-stale:"+n)
    if all((root/n).is_file() for n in files): errors.extend(link_errors(root,files))
    return {"utc":datetime.now(timezone.utc).isoformat(),"mode":mode,"git_repository_detected":tracked is not None,
            "passed":not errors,"errors":sorted(set(errors)),"files":files,"source_rules":rules,
            "ci_executed":False,"published":False,
            "limits":"Static source markers and pattern/allowlist checks are not a semantic proof of runtime behavior or a complete conversation-name/secret detector. Review the allowlisted snapshot before publication."}

def make_package(root: Path, files: list[str], output: Path):
    output.mkdir(parents=True,exist_ok=True)
    data={n:(root/n).read_bytes() for n in files}
    data["SOURCE_FILES.txt"]=("\n".join(sorted(data))+"\n").encode("utf-8")
    sums="".join(digest(v)+"  "+n+"\n" for n,v in sorted(data.items()))
    data["SHA256SUMS.txt"]=sums.encode("utf-8")
    path=output/"ChatGPT-TitleSync-source.zip"
    with zipfile.ZipFile(path,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for n,v in sorted(data.items()):
            info=zipfile.ZipInfo("ChatGPT-TitleSync-source/"+n,date_time=(1980,1,1,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
            z.writestr(info,v)
    sha=digest(path.read_bytes())
    (output/"SHA256SUMS.txt").write_text(sums,encoding="utf-8")
    (output/"ZIP-SHA256.txt").write_text(sha+"  "+path.name+"\n",encoding="utf-8")
    # Reopen the archive and verify all manifest entries against its actual bytes.
    with zipfile.ZipFile(path) as z:
        for line in sums.splitlines():
            expected,name=line.split("  ",1)
            if digest(z.read("ChatGPT-TitleSync-source/"+name))!=expected:raise AuditFailure("zip-manifest-mismatch")
    return {"file":str(path),"sha256":sha,"entries":len(data),"bytes":path.stat().st_size}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root",type=Path,default=Path(__file__).resolve().parents[1])
    ap.add_argument("--output-dir",type=Path)
    ap.add_argument("--allowlist",action="store_true",help="Explicit working-tree candidate mode; still rejects forbidden tracked files")
    ap.add_argument("--no-zip",action="store_true")
    ap.add_argument("--list-files",action="store_true")
    args=ap.parse_args();root=args.root.resolve()
    policy=json.loads((root/"tools/release-policy.json").read_text(encoding="utf-8"))
    report=audit(root,policy,args.allowlist)
    if args.list_files:
        print("\n".join(report["files"]));return 0 if report["passed"] else 1
    out=(args.output_dir or root/"tools/.local"/datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")).resolve()
    out.mkdir(parents=True,exist_ok=True)
    if report["passed"] and not args.no_zip:report["package"]=make_package(root,report["files"],out)
    (out/"release-audit-report.json").write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding="utf-8")
    print(json.dumps({"passed":report["passed"],"mode":report["mode"],"files":len(report["files"]),
                      "errors":report["errors"],"report":str(out/"release-audit-report.json"),
                      "package":report.get("package")},ensure_ascii=False))
    return 0 if report["passed"] else 1
if __name__=="__main__":raise SystemExit(main())
