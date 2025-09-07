import os, re, glob
os.makedirs("artifacts", exist_ok=True)
print("|dataset|mode|AUC|ACC|best|elapsed[s]|")
print("|-|-|-:|-:|-|-:|")
for p in sorted(glob.glob("logs/train-*.log")):
    with open(p, errors="ignore") as f:
        for line in f:
            m = re.search(r"\[RESULT\] ds=(\S+) mode=(\S+) AUC=([\d.]+) ACC=([\d.]+) best=(\{.*?\}) elapsed_sec=(\d+)", line)
            if m:
                print("|" + "|".join(m.groups()) + "|")
