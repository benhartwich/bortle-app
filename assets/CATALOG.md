# assets/catalog.json

The objects the tools without an account offer (lib/catalog.dart): 511 deep-sky
objects with position (J2000), type, size and magnitude.

- **Bortle's curated targets** (49), from the server's
  `services/planner/targets.yaml` — the same list the planner recommends from.
- **OpenNGC** by Mattia Verga, <https://github.com/mattiaverga/OpenNGC>, licensed
  **CC BY-SA 4.0** (<https://creativecommons.org/licenses/by-sa/4.0/>): every
  Messier object but the three stellar ones (M40, M73, M102), and the NGC/IC
  objects brighter than magnitude 9.5 or, for nebulae and clusters, larger than
  20′. Selected and reduced to name, identifiers, type, position, size and
  magnitude; this file, as a derivative, is under the same licence.

Rebuilt with `tool/build_catalog.py` from OpenNGC's `NGC.csv` and `addendum.csv`.
