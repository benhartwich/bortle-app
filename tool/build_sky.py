"""Build assets/sky.json, the stars and constellation figures of the sky map (lib/sky).

From d3-celestial by Olaf Frohn (BSD-3-Clause, https://github.com/ofrohn/d3-celestial,
LICENSES/BSD-3-Clause-d3-celestial.txt), its data/ folder:

- stars.6.json               positions (J2000), V magnitude and B-V; the stars to MAG_LIMIT
- starnames.json             only the proper name ("name") and the Bayer letter with the
                             constellation; the translated names in that file come from
                             Stellarium's sky cultures (GPL) and are deliberately NOT used
- constellations.lines.json  the IAU figures as polylines
- constellations.json        the Latin (IAU) name and the label position; the translated
                             names (from Wikipedia) are not used either

Positions are packed as integers in hundredths of a degree (RA 0..36000), magnitudes and
B-V in hundredths, stars sorted brightest first, so the painter can stop at a limit.

    python3 -I tool/build_sky.py <dir with the four d3-celestial files> assets/sky.json
"""
import json
import sys
from pathlib import Path

MAG_LIMIT = 5.5
NAME_LIMIT = 3.5  # proper names of the stars a tap would hit and someone would know

src, out = Path(sys.argv[1]), Path(sys.argv[2])


def load(name):
    return json.loads((src / name).read_text(encoding="utf-8"))


def ra_dec(coords):
    lon, lat = coords
    ra = lon + 360 if lon < 0 else lon
    return round(ra * 100) % 36000, round(lat * 100)


names = load("starnames.json")
stars = []
for f in load("stars.6.json")["features"]:
    mag = f["properties"]["mag"]
    if mag > MAG_LIMIT:
        continue
    try:
        bv = float(f["properties"].get("bv") or 0)
    except ValueError:
        bv = 0.0
    ra, dec = ra_dec(f["geometry"]["coordinates"])
    stars.append((mag, ra, dec, round(bv * 100), f["id"]))
stars.sort()

flat, labels = [], []
for i, (mag, ra, dec, bv, hip) in enumerate(stars):
    flat += [ra, dec, round(mag * 100), bv]
    n = names.get(str(hip)) or {}
    proper = (n.get("name") or "").strip()
    bayer = (n.get("bayer") or "").strip()
    con = (n.get("c") or "").strip()
    label = proper if proper and mag <= NAME_LIMIT else (f"{bayer} {con}" if bayer and con else "")
    if label:
        labels.append([i, label])

lines = []
for f in load("constellations.lines.json")["features"]:
    polys = []
    for line in f["geometry"]["coordinates"]:
        pts = []
        for c in line:
            pts += ra_dec(c)
        polys.append(pts)
    lines.append([f["id"], polys])

constellations = []
for f in load("constellations.json")["features"]:
    ra, dec = ra_dec(f["geometry"]["coordinates"])
    constellations.append([f["id"], f["properties"]["name"], ra, dec])

doc = {
    "source": "d3-celestial (c) 2015 Olaf Frohn, BSD-3-Clause; see assets/SKY.md",
    "epoch": "J2000",
    "mag_limit": MAG_LIMIT,
    "stars": flat,
    "star_names": labels,
    "lines": lines,
    "constellations": constellations,
}
out.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(stars)} stars, {len(labels)} labels, {len(lines)} figures -> {out} ({out.stat().st_size} bytes)")
