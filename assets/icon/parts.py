# Writes icon.svg, background.svg, foreground.svg and monochrome.svg from one set of parts,
# so the four never drift apart. Run: python3 parts.py
DEFS = """
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0a1230"/><stop offset=".6" stop-color="#04060f"/><stop offset="1" stop-color="#02030a"/>
    </linearGradient>
    <radialGradient id="a1" cx=".15" cy="-.05" r=".8"><stop offset="0" stop-color="#4fe3b0" stop-opacity=".30"/><stop offset=".6" stop-color="#4fe3b0" stop-opacity="0"/></radialGradient>
    <radialGradient id="a2" cx=".9" cy="0" r=".75"><stop offset="0" stop-color="#b48cff" stop-opacity=".34"/><stop offset=".6" stop-color="#b48cff" stop-opacity="0"/></radialGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#8fe3ff"/><stop offset=".45" stop-color="#7aa2f7"/><stop offset="1" stop-color="#b48cff"/>
    </linearGradient>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#02030a"/><stop offset=".62" stop-color="#0b1020"/><stop offset=".86" stop-color="#3a2a2a"/><stop offset="1" stop-color="#f2c06b"/>
    </linearGradient>
    <radialGradient id="core" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#fff8e8"/><stop offset=".35" stop-color="#f6d9a8" stop-opacity=".9"/><stop offset="1" stop-color="#b48cff" stop-opacity="0"/></radialGradient>
    <radialGradient id="halo" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#7aa2f7" stop-opacity=".55"/><stop offset="1" stop-color="#7aa2f7" stop-opacity="0"/></radialGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>
    <clipPath id="dome"><circle cx="512" cy="512" r="300"/></clipPath>
  </defs>"""

BACKGROUND = """
    <rect width="1024" height="1024" fill="url(#bg)"/>
    <rect width="1024" height="1024" fill="url(#a1)"/>
    <rect width="1024" height="1024" fill="url(#a2)"/>"""

# A dark sky over a light-polluted horizon (the Bortle scale, dark above, the town's
# glow below) with a spiral galaxy in it: what the app is for.
def foreground(mono=False):
    ink = "#fff"
    sky = "none" if mono else "url(#sky)"
    ring = ink if mono else "url(#sheen)"
    # A face-on spiral, tilted: two arms leaving the core on opposite sides and winding
    # the same way round it.
    arm = "none" if mono else "#c9d6ff"
    width = 26 if mono else 22
    soft = ""
    galaxy = f"""
      <g transform="translate(520 470) rotate(-25) scale(1 .55)">
        <circle r="200" fill="{'none' if mono else 'url(#halo)'}"/>
        <path d="M 50 0 C 130 -10, 170 -80, 120 -130 C 70 -175, -40 -165, -110 -110" fill="none" stroke="{ink if mono else arm}" stroke-width="{width}" stroke-linecap="round" opacity="{1 if mono else .9}" {soft}/>
        <path d="M -50 0 C -130 10, -170 80, -120 130 C -70 175, 40 165, 110 110" fill="none" stroke="{ink if mono else arm}" stroke-width="{width}" stroke-linecap="round" opacity="{1 if mono else .9}" {soft}/>
        <circle r="{58 if mono else 70}" fill="{ink if mono else 'url(#core)'}"/>
      </g>"""
    stars = f"""
      <g fill="{ink if mono else '#eef1fb'}">
        <circle cx="330" cy="330" r="7"/><circle cx="700" cy="330" r="9"/><circle cx="410" cy="250" r="5"/>
        <circle cx="640" cy="620" r="5"/><circle cx="300" cy="560" r="5"/><circle cx="760" cy="430" r="6"/>
        <path d="M618 270 l8 30 l30 8 l-30 8 l-8 30 l-8 -30 l-30 -8 l30 -8 z"/>
      </g>"""
    horizon = "" if mono else """
      <path d="M190 700 C300 676 420 690 512 682 C610 674 720 690 840 676 L840 840 L190 840 Z" fill="#050816"/>"""
    glow_ring = "" if mono else '<circle cx="512" cy="512" r="300" fill="none" stroke="url(#sheen)" stroke-width="40" filter="url(#glow)" opacity=".7"/>'
    return f"""
    {glow_ring}
    <circle cx="512" cy="512" r="300" fill="{sky}"/>
    <g clip-path="url(#dome)">{stars}{galaxy}{horizon}
    </g>
    <circle cx="512" cy="512" r="300" fill="none" stroke="{ring}" stroke-width="30"/>"""

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{DEFS}{body}\n</svg>\n'

# Adaptive icons crop to a circle of about two thirds: the foreground layers shrink into it.
SAFE = 'transform="translate(512 512) scale(.74) translate(-512 -512)"'
open("icon.svg", "w").write(svg(f"<g>{BACKGROUND}</g><g>{foreground()}</g>"))
open("background.svg", "w").write(svg(f"<g>{BACKGROUND}</g>"))
open("foreground.svg", "w").write(svg(f"<g {SAFE}>{foreground()}</g>"))
open("monochrome.svg", "w").write(svg(f"<g {SAFE}>{foreground(mono=True)}</g>"))
