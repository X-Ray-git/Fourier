"""Generate a macOS-style app icon with rounded corners and glass shine effect."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageMath

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SRC = os.path.join(ROOT, 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png')
DST = os.path.join(ROOT, 'assets/readme-icon.png')
SIZE = 512

src = Image.open(SRC).convert('RGBA')
src = src.resize((SIZE, SIZE), Image.LANCZOS)

radius = int(SIZE * 0.225)
mask = Image.new('L', (SIZE, SIZE), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=radius, fill=255)

result = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
result.paste(src, (0, 0), mask)

grad = Image.new('L', (SIZE, SIZE), 0)
for y in range(SIZE // 3):
    val = int(60 * (1 - y / (SIZE // 3)) ** 0.5)
    stripe = Image.new('L', (SIZE, 1), val)
    grad.paste(stripe, (0, y))

shine_a = ImageMath.unsafe_eval('a * b / 255', a=grad, b=mask).convert('L')
shine = Image.new('RGBA', (SIZE, SIZE), (255, 255, 255, 0))
shine.putalpha(shine_a)
result = Image.alpha_composite(result, shine)

pad = 30
total = SIZE + pad * 2 + 16
final = Image.new('RGBA', (total, total), (0, 0, 0, 0))
shadow = Image.new('RGBA', (total, total), (0, 0, 0, 0))
df = ImageDraw.Draw(shadow)
df.rounded_rectangle((pad, pad + 8, pad + SIZE - 1, pad + SIZE - 1 + 8), radius=radius + 2, fill=(0, 0, 0, 70))
shadow = shadow.filter(ImageFilter.GaussianBlur(radius=10))
final.paste(shadow, (0, 0), shadow)
final.paste(result, (pad, pad), result)

bbox = final.getbbox()
final = final.crop(bbox)
margin = 24
bg = Image.new('RGBA', (final.width + margin * 2, final.height + margin * 2), (0, 0, 0, 0))
bg.paste(final, (margin, margin), final)
bg.save(DST)
print(f'Saved {DST} ({bg.width}x{bg.height})')
