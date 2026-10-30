"""Build assets/catalog.json, the objects of the tools without an account.

Bortle's curated targets (the server's services/planner/targets.yaml) plus, from
OpenNGC (CC BY-SA 4.0, https://github.com/mattiaverga/OpenNGC), every Messier
object and the NGC/IC objects brighter than mag 9.5 or, for nebulae and
clusters, larger than 20'. See assets/CATALOG.md.

    uv run --no-project --with pyyaml python tool/build_catalog.py \
        <dir with OpenNGC NGC.csv and addendum.csv> <bortle>/services/planner/targets.yaml \
        assets/catalog.json
"""
import csv, json, re, sys
from pathlib import Path
import yaml

ngc_dir, targets_yaml, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
TYPES = {"G": "galaxy", "GPair": "galaxy", "GTrpl": "galaxy", "GGroup": "galaxy", "OCl": "open_cluster",
         "GCl": "globular_cluster", "PN": "planetary_nebula", "HII": "emission_nebula", "EmN": "emission_nebula",
         "RfN": "reflection_nebula", "SNR": "supernova_remnant", "Neb": "nebula", "Cl+N": "emission_nebula",
         "*Ass": "open_cluster", "DrkN": "dark_nebula"}

def norm(i):
    m = re.match(r"^(NGC|IC|M)\s*0*(\d+)\s*([A-Z]?)$", i.strip().upper().replace(" ", ""))
    return f"{m.group(1)}{m.group(2)}{m.group(3)}" if m else i.strip().upper().replace(" ", "")

def deg(ra, dec):
    h, m, s = (float(x) for x in ra.split(":"))
    sign = -1 if dec.startswith("-") else 1
    d, dm, ds = (float(x) for x in dec.lstrip("+-").split(":"))
    return round((h + m / 60 + s / 3600) * 15, 4), round(sign * (d + dm / 60 + ds / 3600), 4)

objs = {}
for f in ("NGC.csv", "addendum.csv"):
    for r in csv.DictReader(open(ngc_dir / f, encoding="utf-8"), delimiter=";"):
        t = TYPES.get(r["Type"])
        if not t or not r["RA"]:
            continue
        mag = r["V-Mag"] or r["B-Mag"]
        mag = float(mag) if mag else None
        size = float(r["MajAx"]) if r["MajAx"] else None
        messier = f"M{int(r['M'])}" if r["M"] else None
        if not (messier or (mag is not None and mag <= 9.5) or (size and size >= 20 and t != "galaxy")):
            continue
        ra, dec = deg(r["RA"], r["Dec"])
        ids = [x for x in [messier, norm(r["Name"])] if x]
        names = [n.strip() for n in (r["Common names"] or "").split(",") if n.strip()]
        objs[ids[0]] = {"name": names[0] if names else ids[0], "ids": ids, "type": t, "ra": ra, "dec": dec,
                        "size": size, "mag": mag, "src": "openngc"}

curated = yaml.safe_load(open(targets_yaml))["targets"]
for c in curated:
    ids = [norm(i) for i in c.get("ids", [])]
    key = next((k for k, o in objs.items() if set(ids) & set(o["ids"])), None)
    entry = {"name": c["name"], "ids": ids or [c["name"]], "type": c["type"], "ra": c["ra_deg"], "dec": c["dec_deg"],
             "size": c.get("size_arcmin"), "mag": objs[key]["mag"] if key else None, "src": "bortle",
             "filter": c.get("filter_pref")}
    if key:
        entry["ids"] = list(dict.fromkeys(objs[key]["ids"] + entry["ids"]))
        del objs[key]
    objs[entry["ids"][0]] = entry

rows = sorted(objs.values(), key=lambda o: (o["src"] != "bortle", o["ids"][0][0] != "M",
                                             int(re.sub(r"\D", "", o["ids"][0]) or 0) if o["ids"][0][0] == "M" else 0, o["name"]))
for o in rows:
    for k in [k for k, v in o.items() if v is None]:
        del o[k]
out.write_text(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
print(len(rows), sum(o["src"] == "bortle" for o in rows), sum(any(i.startswith("M") and i[1:].isdigit() for i in o["ids"]) for o in rows))
