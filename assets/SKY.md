# assets/sky.json

The stars and constellation figures of the sky map (lib/sky): 2851 stars to
magnitude 5.5 (position J2000, V magnitude, B-V), the proper names of the
stars to magnitude 3.5 and the Bayer letters of the rest, the 88 IAU
constellation figures as polylines and their Latin names with a label position.

- **d3-celestial** by Olaf Frohn, <https://github.com/ofrohn/d3-celestial>,
  Copyright (c) 2015 Olaf Frohn, licensed **BSD-3-Clause**
  (`LICENSES/BSD-3-Clause-d3-celestial.txt`). Its own sources: the stars from
  XHIP (Anderson & Francis 2012, VizieR V/137D), the star names from the
  HD-DM-GC-HR-HIP-Bayer-Flamsteed cross index (Kostjuk 2002, VizieR IV/27A),
  the figures from the IAU constellation charts with changes by the author.

Deliberately left out: the translated star and constellation names in the same
files. d3-celestial took the star-name translations from Stellarium's sky
cultures (GPL) and the constellation names from Wikipedia (CC BY-SA); neither
is used here, only the Latin IAU names and the English proper names.

Rebuilt with `tool/build_sky.py` from d3-celestial's `data/stars.6.json`,
`starnames.json`, `constellations.lines.json` and `constellations.json`.
