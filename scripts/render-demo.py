#!/usr/bin/env python3
"""Render Momentum's illustrative, silent 24-second product trailer.

Requires Python 3, Pillow, and ffmpeg with libx264.
Run: python3 scripts/render-demo.py
Output: docs/landing/assets/momentum-demo.mp4 and momentum-demo-poster.jpg
This is motion-design footage, not a recording or simulation of the app.
"""
from pathlib import Path
from functools import lru_cache
import math
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/landing/assets'
W, H, FPS, DURATION = 1280, 720, 30, 24
ACCENT = '#b4a2ff'
TEXT = '#eeeef5'
MUTED = '#9694aa'


def font_path(mono=False):
    candidates = (["/System/Library/Fonts/Menlo.ttc",
                   "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"] if mono else
                  ["/System/Library/Fonts/SFNS.ttf",
                   "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"])
    for name in candidates:
        if Path(name).exists():
            return name
    raise RuntimeError('Install DejaVu fonts or adjust font_path() for your system.')


@lru_cache(None)
def font(size, mono=False):
    return ImageFont.truetype(font_path(mono), size)


def text(draw, xy, label, size=16, fill=TEXT, center=False, mono=False):
    f = font(size, mono)
    if center:
        xy = (xy[0] - draw.textlength(label, font=f) / 2, xy[1])
    draw.text(xy, label, font=f, fill=fill)


def ease(value):
    value = max(0, min(1, value))
    return 1 - (1 - value) ** 4


def lerp(a, b, progress):
    return tuple(x + (y - x) * progress for x, y in zip(a, b))


def blend(frame, layer, opacity=1):
    if opacity < 1:
        layer = layer.copy()
        layer.putalpha(layer.getchannel('A').point(lambda x: int(x * max(0, opacity))))
    frame.alpha_composite(layer)


def title_layer(title, subtitle, opacity, shift=0):
    layer = Image.new('RGBA', (W, H))
    draw = ImageDraw.Draw(layer)
    text(draw, (640, 94 + shift), title, 46, center=True)
    text(draw, (640, 154 + shift), subtitle, 18, MUTED, center=True)
    layer.putalpha(layer.getchannel('A').point(lambda x: int(x * opacity)))
    return layer


def make_background():
    # Small blurred color field, upscaled once rather than calculated every frame.
    glow = Image.new('RGB', (160, 90))
    pixels = glow.load()
    for y in range(90):
        for x in range(160):
            strength = math.exp(-(((x - 82) / 53) ** 2 + ((y - 49) / 35) ** 2) * 2)
            pixels[x, y] = (int(11 + strength * 21), int(12 + strength * 15), int(16 + strength * 40))
    return glow.resize((W, H), Image.Resampling.BICUBIC).convert('RGBA')


@lru_cache(None)
def window_art(kind):
    height = 500 if kind == 'editor' else 305
    im = Image.new('RGBA', (800, height))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, 799, height - 1), 14, fill='#141620', outline='#393547', width=2)
    d.rounded_rectangle((2, 2, 797, 48), 12, fill='#20202d')
    d.rectangle((2, 25, 797, 48), fill='#20202d')
    for i, color in enumerate(['#b26166', '#b7975a', '#579577']):
        d.ellipse((17 + i * 17, 18, 25 + i * 17, 26), fill=color)
    titles = {'editor': 'workspace.swift', 'browser': 'Notes', 'terminal': '~/workspace'}
    text(d, (400, 13), titles[kind], 17, '#a09cb3', center=True)
    if kind == 'editor':
        d.rectangle((2, 49, 167, 497), fill='#171924')
        for i, name in enumerate(['workspace', '  Sources', '  focus.swift', '  config.json', '  README.md']):
            if i == 2:
                d.rounded_rectangle((10, 137, 156, 167), 5, fill='#29233e')
            text(d, (18, 72 + i * 34), name, 15, ACCENT if i == 2 else '#818399')
        lines = [('// Less arranging. More doing.', '#71798e'),
                 ('', MUTED), ('import Focus', ACCENT),
                 ('', MUTED), ('let workspace = Desktop()', TEXT),
                 ('workspace.makeRoom(for: .focus)', '#b7cbbf'),
                 ('', MUTED), ('// Pick up where you left off.', '#71798e'),
                 ('workspace.keepTheFlow()', '#b7cbbf')]
        for i, (line, color) in enumerate(lines):
            text(d, (188, 76 + i * 35), str(i + 1), 15, '#484c60', mono=True)
            text(d, (221, 76 + i * 35), line, 19, color, mono=True)
    elif kind == 'browser':
        text(d, (42, 69), 'A SPACE TO THINK', 15, ACCENT)
        text(d, (42, 102), 'Good work needs', 39)
        text(d, (42, 149), 'a little room.', 39)
        text(d, (42, 208), 'Ideas. Research. Whatever comes next.', 18, MUTED)
        for i, width in enumerate([625, 537]):
            d.rounded_rectangle((42, 252 + i * 21, 42 + width, 257 + i * 21), 3, fill='#313141')
    else:
        for i, (line, color) in enumerate([('➜  ~/workspace', ACCENT),
                                          ('', MUTED), ('Ready when you are.', '#a0a4b8'),
                                          ('', MUTED), ('➜', ACCENT)]):
            text(d, (35, 78 + i * 40), line, 23, color, mono=True)
        d.rectangle((72, 239, 83, 263), fill=ACCENT)
    return im


def render_window(frame, kind, rect, active=False, opacity=1):
    x, y, w, h = [int(v) for v in rect]
    if w < 2 or h < 2:
        return
    layer = Image.new('RGBA', (W, H))
    # Scale uniformly so text never stretches when window proportions change.
    source = window_art(kind)
    scaled = source.resize((w, max(1, round(source.height * w / source.width))),
                           Image.Resampling.LANCZOS)
    art = Image.new('RGBA', (w, h), '#141620')
    art.alpha_composite(scaled.crop((0, 0, w, min(h, scaled.height))))
    mask = Image.new('L', (w, h))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), 10, fill=255)
    art.putalpha(mask)
    layer.alpha_composite(art, (x, y))
    if active:
        ImageDraw.Draw(layer).rounded_rectangle((x, y, x + w - 1, y + h - 1), 10,
                                                outline=ACCENT, width=2)
    blend(frame, layer, opacity)


BACKGROUND = make_background()
LAYOUT = {'editor': (157, 267, 546, 320), 'browser': (715, 267, 407, 155),
          'terminal': (715, 434, 407, 153)}
SECOND = {'editor': (576, 267, 546, 320), 'browser': (157, 267, 407, 155),
          'terminal': (157, 434, 407, 153)}


def render(t):
    frame = BACKGROUND.copy()
    d = ImageDraw.Draw(frame)
    text(d, (640, 36), 'M O M E N T U M', 13, ACCENT, center=True)
    text(d, (640, 685), 'CONCEPT DEMO  ·  NATIVE MACOS  ·  KEYBOARD-FIRST', 10, '#6e687f', center=True)
    if t < 3 or t >= 20:
        intro = t < 3
        local = t if intro else t - 20
        opacity = ease(local / .8)
        shift = (1 - ease(local / 1.1)) * 22
        layer = Image.new('RGBA', (W, H))
        ld = ImageDraw.Draw(layer)
        text(ld, (640, 259 + shift), 'Make room for focus.' if intro else 'Find your flow.',
             76 if intro else 84, center=True)
        text(ld, (640, 365 + shift), 'Your windows, in place. Your hands, on the keyboard.' if intro else
             'A little less arranging. A lot more flow.', 23, MUTED, center=True)
        if not intro:
            ld.rounded_rectangle((467, 446, 813, 496), 10, fill='#e8e2ff')
            text(ld, (640, 459), 'Explore the source preview', 19, '#271c44', center=True)
            text(ld, (640, 520), 'github.com/jvrviegas/momentum', 16, '#898198', center=True)
        blend(frame, layer, opacity)
        if intro and t > 2.5:
            dark = BACKGROUND.copy()
            frame = Image.blend(frame, dark, ease((t - 2.5) / .5))
        return frame.convert('RGB')
    local = t - 3
    desktop_opacity = ease(local / .7)
    desktop = Image.new('RGBA', (W, H))
    dd = ImageDraw.Draw(desktop)
    dd.rounded_rectangle((143, 225, 1137, 605), 18, fill='#181924', outline='#454050', width=1)
    dd.rounded_rectangle((144, 226, 1136, 254), 16, fill='#262433')
    dd.rectangle((144, 241, 1136, 254), fill='#262433')
    second = 12 <= t < 16
    text(dd, (164, 232), 'Desktop 2' if second else 'Desktop 1', 12, '#cfcbdf')
    text(dd, (1034, 232), 'Momentum', 12, ACCENT)
    blend(frame, desktop, desktop_opacity)
    rects = LAYOUT.copy()
    focused = 'editor'
    hint = 'Automatic tiling. Your space, organized.'
    if t < 8:
        heading, subtitle = 'Open it. It’s in place.', 'Your layout makes room. You keep moving.'
        for i, kind in enumerate(rects):
            p = ease((local - i * .3) / 1.2)
            rects[kind] = lerp((420 + i * 55, 335 + i * 20, 400, 230), LAYOUT[kind], p)
    elif t < 12:
        heading, subtitle = 'Keep your hands on the keys.', 'Focus and swap without breaking your rhythm.'
        focused = ['editor', 'browser', 'terminal'][min(2, int((t - 8) / 1.05))]
        hint = {'editor': '⌥ H   ·   Focus editor', 'browser': '⌥ L   ·   Focus browser',
                'terminal': '⌥ J   ·   Focus terminal'}[focused]
        if t > 10.8:
            p = ease((t - 10.8) / .65)
            rects['browser'] = lerp(LAYOUT['browser'], (715, 434, 407, 153), p)
            rects['terminal'] = lerp(LAYOUT['terminal'], (715, 267, 407, 155), p)
            hint = '⌥ ⇧ K   ·   Swap windows'
    elif t < 16:
        heading, subtitle = 'Same Mac. A different context.', 'Native Desktops, each with a layout of their own.'
        p = ease((t - 12) / 1.1)
        rects = {kind: lerp(LAYOUT[kind], SECOND[kind], p) for kind in rects}
        hint = '⌥ 2   ·   Switch Desktop'
    else:
        heading, subtitle = 'Structure. With breathing room.', 'Float a window when it needs a little freedom.'
        p = ease((t - 16) / 1)
        rects['editor'] = lerp(SECOND['editor'], LAYOUT['editor'], p)
        rects['browser'] = lerp(SECOND['browser'], LAYOUT['browser'], p)
        rects['terminal'] = lerp(SECOND['terminal'], (621, 370, 448, 230), p)
        focused = 'terminal'
        hint = '⌥ ⇧ Space   ·   Toggle floating'
    title_opacity = ease((t - (3 if t < 8 else 8 if t < 12 else 12 if t < 16 else 16)) / .5)
    frame.alpha_composite(title_layer(heading, subtitle, title_opacity, (1 - title_opacity) * 10))
    for kind in ['editor', 'browser', 'terminal']:
        reveal = ease((local - ['editor', 'browser', 'terminal'].index(kind) * .3) / .7)
        render_window(frame, kind, rects[kind], kind == focused, reveal)
    overlay = Image.new('RGBA', (W, H))
    od = ImageDraw.Draw(overlay)
    width = od.textlength(hint, font=font(14)) + 42
    od.rounded_rectangle((640 - width / 2, 631, 640 + width / 2, 665), 9,
                         fill='#201c2d', outline='#493b68')
    text(od, (640, 639), hint, 14, '#c4b5f5', center=True)
    blend(frame, overlay, desktop_opacity)
    if t > 19.5:
        frame = Image.blend(frame, BACKGROUND, ease((t - 19.5) / .5))
    return frame.convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Poster has a readable headline and a complete tiled workspace.
    render(5).save(OUT / 'momentum-demo-poster.jpg', quality=94)
    command = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
               '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-an', '-c:v', 'libx264',
               '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p',
               '-movflags', '+faststart', str(OUT / 'momentum-demo.mp4')]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    try:
        for index in range(FPS * DURATION):
            process.stdin.write(render(index / FPS).tobytes())
        process.stdin.close()
        if process.wait() != 0:
            raise RuntimeError('ffmpeg encoding failed')
    except BaseException:
        process.kill()
        process.wait()
        raise
    print(f'Rendered {DURATION}s at {W}×{H}, {FPS} fps: {OUT / "momentum-demo.mp4"}')


if __name__ == '__main__':
    main()
