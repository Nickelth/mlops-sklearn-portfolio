#!/usr/bin/env python3
import hashlib, json, os, glob, time, sys
def sha256(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20), b''): h.update(b)
    return h.hexdigest()
items=[]
for pat in ("models/model_*.joblib","artifacts/summary_*.json",
            "artifacts/cv_results_*.csv","logs/*.log"):
    for p in sorted(glob.glob(pat)):
        if not os.path.isfile(p): continue
        st=os.stat(p)
        items.append({"path":p,"bytes":st.st_size,"sha256":sha256(p),"mtime":int(st.st_mtime)})
os.makedirs("artifacts", exist_ok=True)
json.dump({"generated_utc":time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),"items":items},
          open("artifacts/manifest.json","w"), indent=2)
print("wrote artifacts/manifest.json with", len(items), "entries")
