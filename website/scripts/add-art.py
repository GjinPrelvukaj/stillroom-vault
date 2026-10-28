"""Adds a generated image to an art slot: public/art/<slot>.webp.

The images are printed on a warm paper a little darker than the site's. This turns that paper into the site's own
(each channel scaled so a little under the median colour of the image's border, grain included, comes out as the
page's paper, #f7f6f2), so the drawing sits on the page with no visible box. Needs Pillow.

    python3 scripts/add-art.py ~/Downloads/keys.png learn-compare [more image/slot pairs...]

With --plate first, the paper is kept as printed, grain and all: for slots shown as a framed plate (the home plate,
Learn more, the cards, the pricing tiers, the menu), where the texture is the point.

With --wash first, the image is one of the faint paper washes laid behind pages (ART.md, "Paper washes"): its paper
becomes clear, keeping only what is darker than it as ink exactly as it would print on the site's paper, so it lays
over a page with no box, at whatever strength the page's CSS gives it.
"""
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageMath

MAX = 1600  # longest side, in pixels
SMALL = 800  # the phone-size copy's longest side: <slot>-800.webp, offered through srcset
GRAIN = 0.93  # how far under the paper's colour counts as paper: low enough that its grain goes too
PAGE = (247, 246, 242)  # --paper in src/styles/tokens.css
WASH_MAX = {'wash': 1400, 'side': 1000, 'pattern': 800}  # paper washes are soft and faint: this is plenty

args = sys.argv[1:]
plate = bool(args) and args[0] == '--plate'
wash = bool(args) and args[0] == '--wash'
if plate or wash:
    args = args[1:]
if not args or len(args) % 2:
    sys.exit(__doc__)
out = Path(__file__).resolve().parent.parent / 'public' / 'art'
out.mkdir(parents=True, exist_ok=True)
def small(im, slot, quality):
    """The same picture at phone size, for the pages' srcset (Art.astro, BannerHero, the home plate)."""
    s = im.copy()
    s.thumbnail((SMALL, SMALL), Image.LANCZOS)
    s.save(out / f'{slot}-{SMALL}.webp', quality=quality, method=6)


for src, slot in zip(args[::2], args[1::2]):
    im = Image.open(src).convert('RGB')
    im.thumbnail((MAX, MAX), Image.LANCZOS)
    w, h = im.size
    border = [im.getpixel((x, y)) for x in range(0, w, 8) for y in (2, h - 3)]
    border += [im.getpixel((x, y)) for y in range(0, h, 8) for x in (2, w - 3)]
    if wash:
        # The paper is what most of the sheet is: each channel's upper quartile. Each pixel then becomes ink with an
        # alpha, chosen so that laid over the page's paper it gives exactly paper × (pixel / paper), as if multiplied:
        # plain paper turns transparent and only the faint marks remain, laid normally over anything.
        side = WASH_MAX.get(slot.split('-')[0], 1200)
        im.thumbnail((side, side), Image.LANCZOS)
        im = im.filter(ImageFilter.GaussianBlur(0.8))  # the paper's grain is invisible this faint, and costs bytes
        bands = im.split()
        paper = [sorted(b.getdata())[b.width * b.height * 3 // 4] for b in bands]
        c = [b.point(lambda v, p=p: min(255, round(v * 255 / p))) for b, p in zip(bands, paper)]
        m = ImageChops.darker(ImageChops.darker(c[0], c[1]), c[2])  # the darkest channel sets the ink's strength
        alpha = ImageChops.invert(m).point(lambda v: 0 if v < 6 else v)  # fainter than 2%: plain paper
        ink = [
            ImageMath.lambda_eval(
                lambda e, P=P: e['convert'](e['float'](e['c'] - e['m']) * P / e['max'](e['float'](e['a']), 1.0), 'L'),
                c=ch, m=m, a=alpha,
            )
            for ch, P in zip(c, PAGE)
        ]
        Image.merge('RGBA', [*ink, alpha]).save(out / f'{slot}.webp', quality=72, alpha_quality=60, method=6)
        print(f'{slot}: paper {paper} made clear, for laying over the page')
        continue
    if plate:
        im.save(out / f'{slot}.webp', quality=82, method=6)
        small(im, slot, 82)
        print(f'{slot}: kept as printed, for a plate')
        continue
    paper = [statistics.median(p[i] for p in border) for i in range(3)]
    bands = [b.point(lambda v, k=t / (p * GRAIN), t=t: min(t, round(v * k))) for b, p, t in zip(im.split(), paper, PAGE)]
    merged = Image.merge('RGB', bands)
    merged.save(out / f'{slot}.webp', quality=80, method=6)
    small(merged, slot, 80)
    print(f'{slot}: paper {[round(p) for p in paper]} matched to the page')
