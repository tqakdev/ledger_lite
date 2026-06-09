#!/usr/bin/env python3
"""Compose App Store screenshots at multiple sizes: teal gradient + headline + device.

A single 1320x2868 design `.stage` is scaled into each target canvas, so the 6.9" and
6.5" sets are pixel-faithful to each other.
"""
import base64, subprocess, pathlib, html

RAW = pathlib.Path("/tmp/ll_shots/raw")
HTMLDIR = pathlib.Path("/tmp/ll_html"); HTMLDIR.mkdir(exist_ok=True)
# Output beside this script, wherever the repo is checked out.
BASE = pathlib.Path(__file__).resolve().parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# (raw file, headline html with <span class=a> accent, subhead)
SLIDES = [
    ("01-runway",
     'Know exactly what’s<br><span class="a">safe to spend.</span>',
     'A daily safe-to-spend that already subtracts the bills heading your way — all the way to payday.'),
    ("02-whatif",
     '<span class="a">What if</span> you spend<br>$150 today?',
     'Test any purchase against payday before you commit. No bank-linked app can show you this.'),
    ("03-bills",
     'Every bill,<br><span class="a">netted out</span> for you.',
     'Your subscriptions feed the forecast automatically — so the safe-to-spend number always tells the truth.'),
    ("04-scan",
     'Snap a receipt.<br><span class="a">It fills itself in.</span>',
     'On-device OCR reads the total, merchant and date in seconds. Nothing is ever uploaded.'),
    ("05-spending",
     'Every expense,<br><span class="a">in seconds.</span>',
     'A fast daily log with full-text search — every entry stored privately on your iPhone.'),
]

# target sets: (folder, width, height)
TARGETS = [("6.9-inch", 1320, 2868), ("6.5-inch", 1242, 2688)]

DEV_W = 904  # inner device width in design units (1320-wide stage)

TEMPLATE = """<!doctype html><html><head><meta charset="utf-8"><style>
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; background:#04201F; }}
.stage {{
  position:relative; width:1320px; height:2868px;
  transform:scale({f}); transform-origin:top left;
  font-family:-apple-system,"SF Pro Display","Helvetica Neue",sans-serif;
  background:
    radial-gradient(1200px 900px at 12% 4%, rgba(43,212,196,.20), transparent 60%),
    radial-gradient(1000px 1000px at 96% 30%, rgba(20,150,140,.18), transparent 55%),
    linear-gradient(150deg,#0D5650 0%,#08403C 38%,#05282680 60%,#04201F 100%);
}}
.glow {{ position:absolute; left:50%; top:1640px; transform:translateX(-50%);
  width:1180px; height:1180px; border-radius:50%;
  background:radial-gradient(circle, rgba(43,212,196,.22), transparent 62%); filter:blur(40px); }}
.wrap {{ position:relative; padding:108px 116px 0 116px; }}
.brand {{ display:flex; align-items:center; gap:16px; margin-bottom:74px; }}
.brand .dot {{ width:30px; height:30px; border-radius:9px;
  background:linear-gradient(140deg,#34E3D2,#14A99B); box-shadow:0 0 22px rgba(52,227,210,.6); }}
.brand .name {{ color:#CFF3EE; font-size:30px; font-weight:700; letter-spacing:7px; }}
h1 {{ color:#FFFFFF; font-weight:800; font-size:96px; line-height:1.04; letter-spacing:-2.4px; }}
h1 .a {{ color:#34E3D2; }}
p.sub {{ margin-top:34px; max-width:1010px; color:#A6D8D1; font-size:38px;
  font-weight:500; line-height:1.36; letter-spacing:-.3px; }}
.device {{ position:absolute; left:50%; bottom:84px; transform:translateX(-50%);
  width:{dev_w}px; padding:13px; border-radius:78px;
  background:linear-gradient(160deg,#0a1f1d,#020c0b);
  box-shadow:0 70px 130px rgba(0,0,0,.55), 0 12px 40px rgba(0,0,0,.4),
    inset 0 0 0 1.5px rgba(120,220,210,.18); }}
.device img {{ display:block; width:100%; border-radius:66px; }}
</style></head><body>
<div class="stage">
  <div class="glow"></div>
  <div class="wrap">
    <div class="brand"><div class="dot"></div><div class="name">LEDGER LITE</div></div>
    <h1>{headline}</h1>
    <p class="sub">{sub}</p>
  </div>
  <div class="device"><img src="data:image/png;base64,{img}"></div>
</div>
</body></html>"""

for folder, W, H in TARGETS:
    out = BASE / folder; out.mkdir(parents=True, exist_ok=True)
    f = W / 1320.0
    for name, headline, sub in SLIDES:
        b64 = base64.b64encode((RAW / f"{name}.png").read_bytes()).decode()
        doc = TEMPLATE.format(W=W, H=H, f=f, dev_w=DEV_W,
                              headline=headline, sub=html.escape(sub).replace("&#x27;", "’"), img=b64)
        hp = HTMLDIR / f"{folder}-{name}.html"; hp.write_text(doc)
        op = out / f"{name}.png"
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-sandbox",
            "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--window-size={W},{H}", f"--screenshot={op}", f"file://{hp}"],
            check=True, capture_output=True)
        # flatten to opaque RGB (App Store rejects alpha)
        from PIL import Image
        im = Image.open(op)
        if im.mode != "RGB":
            bg = Image.new("RGBA", im.size, (4, 32, 31, 255))
            Image.alpha_composite(bg, im.convert("RGBA")).convert("RGB").save(op)
    print(f"{folder}: 5 frames at {W}x{H}")
print("DONE")
