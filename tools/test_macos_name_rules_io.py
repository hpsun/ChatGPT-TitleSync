"""CLI-only macOS name-rule I/O checks. Uses private temporary files; never opens an editor or reads an app."""
import argparse,json,os,subprocess,tempfile
from pathlib import Path

def run(helper):
    rows=[]
    with tempfile.TemporaryDirectory(prefix="cts-rules-mac-io-") as d:
        d=Path(d);raw="Example \u793a\u4f8b \U0001f600";packet=raw.encode("utf-16-le")
        def case(name,path,code,prefix):
            ip,op,sp=d/(name+".input"),d/(name+".output"),d/(name+".status")
            ip.write_bytes(packet)
            proc=subprocess.run([str(helper),"--format","--rules",str(path),"--input",str(ip),"--output",str(op),"--status",str(sp)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=2)
            status=sp.read_text(encoding="ascii");assert proc.returncode==code,(name,proc.returncode,status)
            assert op.read_bytes()==packet,(name,"raw fallback was not exact")
            assert status.startswith(prefix),(name,status)
            rows.append({"case":name,"exit":proc.returncode,"status":status,"rawExact":True})
        missing=d/"absent-parent"/"title-rules.json"
        case("missing-parent",missing,0,"ok");assert not missing.parent.exists()
        folder=d/"rules-directory";folder.mkdir();case("directory",folder,3,"fallback:RulesReadFailed")
        oversized=d/"oversized.json";oversized.write_bytes(b"x"*131073);case("oversized",oversized,2,"fallback:RulesTooLarge")
        invalid=d/"invalid.json";invalid.write_bytes(b"{");case("bad-json",invalid,2,"fallback:ParseError")
        if os.name=="posix" and os.geteuid()!=0:
            denied=d/"denied.json";denied.write_bytes(b"{}");denied.chmod(0)
            try:case("read-denied",denied,3,"fallback:RulesReadFailed")
            finally:denied.chmod(0o600)
        else:rows.append({"case":"read-denied","skipped":"requires non-root POSIX permissions"})
    return {"passed":True,"scope":"private files and --format only; no AppKit editor/AX/native caption", "cases":rows}
if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--helper",type=Path,required=True);p.add_argument("--output",type=Path);a=p.parse_args()
    r=run(a.helper.resolve());text=json.dumps(r,indent=2)
    if a.output:a.output.write_text(text+"\n",encoding="utf-8")
    print(text)
