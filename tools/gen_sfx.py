#!/usr/bin/env python3
"""
Procedural SFX + ambience generator for "Bao Ve Dem".
Pure standard-library synthesis (no numpy). Outputs 16-bit PCM WAV.

These are PLACEHOLDER sounds, synthesized so the game feels alive immediately.
Swap them with real Freesound/Suno/ElevenLabs assets later (same filenames).

Run:  python tools/gen_sfx.py
"""
import wave, struct, math, random, os

SR = 44100
random.seed(20260621)  # deterministic output

SFX_DIR   = os.path.join("assets", "audio", "sfx")
MUSIC_DIR = os.path.join("assets", "audio", "music")
JUMP_DIR  = os.path.join("assets", "audio", "jumpscare")
for d in (SFX_DIR, MUSIC_DIR, JUMP_DIR):
    os.makedirs(d, exist_ok=True)

# ---------------------------------------------------------------- helpers
def buf(dur):
    return [0.0] * int(SR * dur)

def add(dst, src, at=0.0, gain=1.0):
    start = int(at * SR)
    for i, s in enumerate(src):
        j = start + i
        if 0 <= j < len(dst):
            dst[j] += s * gain
    return dst

def sine(freq, dur, phase=0.0):
    n = int(SR * dur)
    return [math.sin(2 * math.pi * freq * (i / SR) + phase) for i in range(n)]

def saw(freq, dur):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = (i / SR) * freq
        out.append(2.0 * (t - math.floor(t + 0.5)))
    return out

def square(freq, dur, duty=0.5):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = (i / SR) * freq
        frac = t - math.floor(t)
        out.append(1.0 if frac < duty else -1.0)
    return out

def noise(dur):
    n = int(SR * dur)
    return [random.uniform(-1, 1) for _ in range(n)]

def adsr(samples, a=0.01, d=0.05, s=0.7, r=0.1):
    n = len(samples)
    if n == 0:
        return samples
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    ns = max(0, n - na - nd - nr)
    out = []
    for i in range(n):
        if i < na:
            g = i / max(1, na)
        elif i < na + nd:
            g = 1.0 - (1.0 - s) * ((i - na) / max(1, nd))
        elif i < na + nd + ns:
            g = s
        else:
            k = (i - na - nd - ns) / max(1, nr)
            g = s * (1.0 - k)
        out.append(samples[i] * g)
    return out

def exp_decay(samples, tau):
    return [s * math.exp(-(i / SR) / tau) for i, s in enumerate(samples)]

def lowpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * max(1.0, cutoff))
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    y, out = 0.0, []
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out

def highpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * max(1.0, cutoff))
    dt = 1.0 / SR
    alpha = rc / (rc + dt)
    out, yprev, xprev = [], 0.0, 0.0
    for x in samples:
        y = alpha * (yprev + x - xprev)
        out.append(y)
        yprev, xprev = y, x
    return out

def bandpass(samples, low, high):
    return highpass(lowpass(samples, high), low)

def normalize(samples, peak=0.9):
    if samples and isinstance(samples[0], tuple):
        m = max((max(abs(l), abs(r)) for l, r in samples), default=0.0)
        if m == 0:
            return samples
        g = peak / m
        return [(l * g, r * g) for l, r in samples]
    m = max((abs(s) for s in samples), default=0.0)
    if m == 0:
        return samples
    g = peak / m
    return [s * g for s in samples]

def soft_clip(samples):
    return [math.tanh(s) for s in samples]

def save(name, samples, folder=SFX_DIR, stereo=False, peak=0.9):
    samples = normalize(samples, peak)
    path = os.path.join(folder, name)
    with wave.open(path, "w") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        if stereo:
            # samples is a list of (L, R)
            for l, r in samples:
                frames += struct.pack("<hh",
                                      int(max(-1, min(1, l)) * 32767),
                                      int(max(-1, min(1, r)) * 32767))
        else:
            for s in samples:
                frames += struct.pack("<h", int(max(-1, min(1, s)) * 32767))
        w.writeframes(bytes(frames))
    dur = len(samples) / SR
    print(f"  {name:28s} {dur:5.2f}s  {os.path.getsize(path)//1024} KB")

# ---------------------------------------------------------------- UI
def ui_click():
    s = adsr(sine(1180, 0.06), a=0.001, d=0.02, s=0.2, r=0.03)
    s = add(s, adsr(sine(1760, 0.05), a=0.001, d=0.01, s=0.1, r=0.03), gain=0.4)
    save("ui_click.wav", s, peak=0.6)

def ui_hover():
    s = adsr(sine(760, 0.05), a=0.002, d=0.02, s=0.15, r=0.02)
    save("ui_hover.wav", s, peak=0.35)

def ui_back():
    s = buf(0.18)
    add(s, exp_decay(sine(700, 0.09), 0.05), 0.0, 0.6)
    add(s, exp_decay(sine(480, 0.10), 0.05), 0.07, 0.6)
    save("ui_back.wav", s, peak=0.5)

def ui_confirm():
    s = buf(0.3)
    add(s, exp_decay(sine(620, 0.12), 0.06), 0.0, 0.6)
    add(s, exp_decay(sine(930, 0.18), 0.08), 0.08, 0.6)
    save("ui_confirm.wav", s, peak=0.55)

# ---------------------------------------------------------------- clock
def clock_tick():
    # mechanical tick: short noise transient + tiny low thud
    n = bandpass(noise(0.03), 1500, 6000)
    n = exp_decay(n, 0.006)
    thud = exp_decay(sine(160, 0.04), 0.01)
    s = buf(0.06)
    add(s, n, 0.0, 0.9)
    add(s, thud, 0.0, 0.3)
    save("clock_tick.wav", s, peak=0.5)

def clock_chime():
    # bell-ish hour chime (inharmonic partials)
    s = buf(1.6)
    base = 523.25
    for mult, g, tau in [(1.0, 1.0, 0.9), (2.76, 0.6, 0.6),
                          (5.40, 0.35, 0.4), (8.93, 0.2, 0.25)]:
        add(s, exp_decay(sine(base * mult, 1.6), tau), 0.0, g)
    save("clock_chime.wav", s, peak=0.7)

# ---------------------------------------------------------------- doors / lights
def _shutter_slide(dur, rate_hz, fade="in"):
    # Rattly metal roller-shutter slide: segmented noise (each "segment" of the
    # roller passing the guide) band-limited to a metallic range.
    n = int(SR * dur)
    seg = []
    for i in range(n):
        t = i / SR
        rattle = 1.0 if (math.sin(t * 2 * math.pi * rate_hz) > -0.2) else 0.32
        if fade == "in":
            env = min(1.0, t / 0.04)
        else:  # fade out as the door rolls up and away
            env = max(0.0, 1.0 - t / dur)
        seg.append(random.uniform(-1, 1) * rattle * env)
    return bandpass(seg, 360, 2600)

def door_slam():
    # CLOSING: shutter rolls DOWN, then a solid clunk as it meets the floor.
    s = buf(0.7)
    add(s, _shutter_slide(0.30, 26, "in"), 0.0, 0.5)
    clunk = exp_decay(sine(82, 0.4), 0.10)
    clunk = add(clunk, exp_decay(sine(120, 0.3), 0.08), gain=0.6)
    clunk = add(clunk, exp_decay(bandpass(noise(0.2), 150, 2000), 0.04), gain=0.55)
    add(s, clunk, 0.29, 1.0)
    add(s, exp_decay(sine(430, 0.22), 0.07), 0.31, 0.10)  # faint metal ring
    save("door_slam.wav", soft_clip(s), peak=0.92)

def door_creak():
    # OPENING: a latch release clunk, then the shutter rolls UP and fades away.
    s = buf(0.7)
    rel = exp_decay(sine(110, 0.2), 0.05)
    rel = add(rel, exp_decay(bandpass(noise(0.1), 200, 2500), 0.02), gain=0.6)
    add(s, rel, 0.0, 0.7)
    add(s, _shutter_slide(0.40, 24, "out"), 0.06, 0.42)
    save("door_creak.wav", soft_clip(s), peak=0.7)

def light_switch():
    s = buf(0.12)
    add(s, exp_decay(bandpass(noise(0.02), 800, 5000), 0.004), 0.0, 1.0)
    add(s, exp_decay(sine(220, 0.03), 0.008), 0.0, 0.4)
    add(s, exp_decay(bandpass(noise(0.02), 800, 5000), 0.004), 0.05, 0.5)
    save("light_switch.wav", s, peak=0.6)

def fluorescent_hum():
    # 2s loopable mains hum (100 Hz + harmonics) with flicker
    dur = 2.0
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        flick = 1.0 + 0.05 * math.sin(t * 7.0) + 0.03 * random.uniform(-1, 1)
        v = (0.6 * math.sin(2 * math.pi * 100 * t)
             + 0.3 * math.sin(2 * math.pi * 200 * t)
             + 0.15 * math.sin(2 * math.pi * 300 * t))
        out.append(v * flick * 0.25)
    save("fluorescent_hum.wav", out, peak=0.3)

# ---------------------------------------------------------------- cameras
def camera_switch():
    s = buf(0.35)
    # CRT static burst
    st = bandpass(noise(0.3), 500, 9000)
    st = adsr(st, a=0.005, d=0.05, s=0.4, r=0.2)
    add(s, st, 0.0, 0.8)
    # tuning click
    add(s, exp_decay(sine(1400, 0.03), 0.008), 0.0, 0.5)
    save("camera_switch.wav", s, peak=0.55)

def static_loop():
    st = bandpass(noise(2.0), 400, 9000)
    save("static_loop.wav", st, peak=0.35)

def camera_up():
    s = buf(0.4)
    sweep = []
    n = int(SR * 0.3)
    for i in range(n):
        t = i / SR
        f = 200 + 1800 * (t / 0.3)
        sweep.append(math.sin(2 * math.pi * f * t))
    add(s, adsr(sweep, a=0.01, d=0.05, s=0.5, r=0.1), 0.0, 0.4)
    add(s, exp_decay(bandpass(noise(0.2), 600, 6000), 0.06), 0.0, 0.4)
    save("camera_up.wav", s, peak=0.5)

def camera_down():
    s = buf(0.4)
    sweep = []
    n = int(SR * 0.3)
    for i in range(n):
        t = i / SR
        f = 2000 - 1800 * (t / 0.3)
        sweep.append(math.sin(2 * math.pi * f * t))
    add(s, adsr(sweep, a=0.01, d=0.05, s=0.5, r=0.1), 0.0, 0.4)
    add(s, exp_decay(bandpass(noise(0.2), 600, 6000), 0.06), 0.0, 0.4)
    save("camera_down.wav", s, peak=0.5)

# ---------------------------------------------------------------- tension / body
def heartbeat():
    # ~1.0s loop, two thumps "lub-dub"
    s = buf(1.0)
    def thump(f, dur):
        return exp_decay(sine(f, dur), 0.05)
    add(s, thump(60, 0.25), 0.05, 1.0)
    add(s, thump(50, 0.25), 0.30, 0.7)
    save("heartbeat.wav", soft_clip(s), peak=0.8)

def breathing():
    # 3s loop: inhale (noise rising) + exhale (noise falling)
    s = buf(3.0)
    inhale = lowpass(noise(0.9), 1200)
    inhale = adsr(inhale, a=0.4, d=0.1, s=0.6, r=0.3)
    exhale = lowpass(noise(1.0), 900)
    exhale = adsr(exhale, a=0.1, d=0.2, s=0.5, r=0.6)
    add(s, inhale, 0.1, 0.5)
    add(s, exhale, 1.4, 0.45)
    save("breathing.wav", s, peak=0.4)

def whisper():
    # unsettling layered whisper (filtered modulated noise)
    n = int(SR * 2.2)
    out = []
    for i in range(n):
        t = i / SR
        mod = 0.5 + 0.5 * abs(math.sin(t * 5.5))
        out.append(random.uniform(-1, 1) * mod)
    out = bandpass(out, 700, 3000)
    out = adsr(out, a=0.3, d=0.2, s=0.6, r=0.6)
    save("whisper.wav", out, peak=0.35)

# ---------------------------------------------------------------- stings / jumpscare
def jumpscare():
    dur = 1.4
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        # dense detuned high cluster sliding down = classic screech
        f0 = 1400 * math.exp(-t * 1.2) + 120
        v = 0.0
        for det in (0.99, 1.0, 1.01, 1.337, 1.66):
            v += math.sin(2 * math.pi * f0 * det * t)
        v /= 5.0
        v += 0.7 * random.uniform(-1, 1)  # harsh noise
        out.append(v)
    out = bandpass(out, 200, 9000)
    # massive low impact at the front
    out = add(out, exp_decay(sine(55, 0.8), 0.2), 0.0, 1.4)
    out = adsr(out, a=0.001, d=0.1, s=0.85, r=0.4)
    save("jumpscare.wav", soft_clip(out), folder=JUMP_DIR, peak=0.99)

def stinger():
    # short dread hit for scares that aren't a game over
    s = buf(1.0)
    add(s, exp_decay(sine(110, 0.8), 0.3), 0.0, 1.0)
    add(s, exp_decay(sine(110 * 1.5, 0.8), 0.25), 0.0, 0.4)
    add(s, exp_decay(bandpass(noise(0.5), 300, 4000), 0.1), 0.0, 0.5)
    save("stinger.wav", soft_clip(s), peak=0.85)

def power_down():
    # descending de-energize + hum dying
    n = int(SR * 1.6)
    out = []
    for i in range(n):
        t = i / SR
        f = 300 * math.exp(-t * 1.5) + 40
        amp = math.exp(-t * 1.1)
        out.append((0.6 * math.sin(2 * math.pi * f * t)
                    + 0.2 * math.sin(2 * math.pi * 100 * (1 - t / 1.6))) * amp)
    save("power_down.wav", out, peak=0.7)

def low_power_beep():
    s = adsr(square(880, 0.18, 0.5), a=0.005, d=0.02, s=0.8, r=0.03)
    save("low_power_beep.wav", s, peak=0.45)

# ---------------------------------------------------------------- folk / items
def offering_bell():
    # singing-bowl / small temple bell (gentle, respectful)
    s = buf(1.8)
    base = 660
    for mult, g, tau in [(1.0, 1.0, 1.1), (2.7, 0.5, 0.7), (4.2, 0.25, 0.5)]:
        add(s, exp_decay(sine(base * mult, 1.8), tau), 0.0, g)
    save("offering_bell.wav", s, peak=0.6)

def incense_whoosh():
    # soft airy whoosh for using an item / lighting incense
    n = int(SR * 0.6)
    out = bandpass(noise(0.6), 400, 4000)
    sh = []
    for i, x in enumerate(out):
        t = i / SR
        env = math.sin(math.pi * (t / 0.6)) if t < 0.6 else 0.0
        sh.append(x * env)
    save("incense_whoosh.wav", sh, peak=0.45)

def item_good():
    s = buf(0.6)
    add(s, exp_decay(sine(660, 0.25), 0.12), 0.0, 0.6)
    add(s, exp_decay(sine(990, 0.3), 0.14), 0.1, 0.6)
    add(s, exp_decay(sine(1320, 0.35), 0.16), 0.2, 0.5)
    save("item_good.wav", s, peak=0.55)

def item_bad():
    # dissonant, "uh oh you got cursed"
    s = buf(0.8)
    add(s, exp_decay(sine(330, 0.5), 0.25), 0.0, 0.6)
    add(s, exp_decay(sine(349, 0.5), 0.25), 0.0, 0.6)  # minor 2nd beat
    add(s, exp_decay(sine(220, 0.6), 0.3), 0.15, 0.5)
    save("item_bad.wav", soft_clip(s), peak=0.6)

# ---------------------------------------------------------------- world
def footstep_wood():
    s = buf(0.22)
    add(s, exp_decay(sine(120, 0.12), 0.03), 0.0, 0.8)
    add(s, exp_decay(bandpass(noise(0.1), 200, 1800), 0.02), 0.0, 0.5)
    save("footstep_wood.wav", s, peak=0.5)

def knock():
    s = buf(1.3)
    def k(at):
        imp = exp_decay(sine(180, 0.12), 0.025)
        imp = add(imp, exp_decay(bandpass(noise(0.08), 200, 2500), 0.015), gain=0.6)
        add(s, imp, at, 1.0)
    k(0.0); k(0.45); k(0.9)
    save("knock.wav", soft_clip(s), peak=0.8)

def rooster():
    # synth "o-o-o" crow: three formant-swept segments
    s = buf(1.3)
    def crow_seg(at, dur, f_start, f_end):
        n = int(SR * dur)
        seg = []
        for i in range(n):
            t = i / SR
            f = f_start + (f_end - f_start) * (t / dur)
            # buzzy voice = sum of harmonics
            v = 0.0
            for h in range(1, 6):
                v += (1.0 / h) * math.sin(2 * math.pi * f * h * t)
            seg.append(v)
        seg = adsr(seg, a=0.02, d=0.05, s=0.7, r=0.08)
        add(s, seg, at, 1.0)
    crow_seg(0.0, 0.18, 500, 700)
    crow_seg(0.22, 0.30, 700, 900)
    crow_seg(0.58, 0.45, 850, 600)
    save("rooster.wav", soft_clip(s), peak=0.7)

def vendor_bell():
    # little hand-bell the hang rong vendor might ring
    s = buf(0.8)
    for mult, g, tau in [(1.0, 1.0, 0.4), (2.5, 0.6, 0.3), (3.8, 0.3, 0.2)]:
        add(s, exp_decay(sine(1100 * mult, 0.8), tau), 0.0, g)
    save("vendor_bell.wav", s, peak=0.55)

# ---------------------------------------------------------------- ambience (stereo)
def ambience_night():
    dur = 14.0
    n = int(SR * dur)
    left = [0.0] * n
    right = [0.0] * n
    # low drone (two detuned oscillators)
    for i in range(n):
        t = i / SR
        d = (0.5 * math.sin(2 * math.pi * 55 * t)
             + 0.45 * math.sin(2 * math.pi * 55.4 * t)
             + 0.2 * math.sin(2 * math.pi * 110 * t))
        d *= 0.12 * (0.9 + 0.1 * math.sin(t * 0.3))
        left[i] += d
        right[i] += d * 0.95
    # crickets: short high chirps scattered, panned
    def chirp(at, freq, pan):
        cn = int(SR * 0.12)
        seg = []
        for i in range(cn):
            t = i / SR
            trill = 1.0 if (math.sin(t * 2 * math.pi * 40) > 0) else 0.2
            env = math.sin(math.pi * (t / 0.12))
            seg.append(math.sin(2 * math.pi * freq * t) * env * trill)
        start = int(at * SR)
        for i, sm in enumerate(seg):
            j = start + i
            if 0 <= j < n:
                left[j] += sm * 0.18 * (1.0 - pan)
                right[j] += sm * 0.18 * pan
    tt = 0.0
    while tt < dur:
        chirp(tt, random.choice([3800, 4200, 4600, 5000]), random.random())
        tt += random.uniform(0.18, 0.5)
    # distant dog bark occasionally
    def dog(at, pan):
        bn = int(SR * 0.25)
        seg = []
        for i in range(bn):
            t = i / SR
            f = 300 - 120 * (t / 0.25)
            seg.append(0.6 * math.sin(2 * math.pi * f * t) + 0.3 * random.uniform(-1, 1))
        seg = lowpass(seg, 1200)
        seg = adsr(seg, a=0.01, d=0.05, s=0.5, r=0.1)
        start = int(at * SR)
        for i, sm in enumerate(seg):
            j = start + i
            if 0 <= j < n:
                left[j] += sm * 0.10 * (1.0 - pan)
                right[j] += sm * 0.10 * pan
    for at in (2.7, 6.4, 11.1):
        dog(at, random.random())
    # distant motorbike whoosh (Vietnamese night detail)
    def moto(at):
        mn = int(SR * 1.6)
        seg = []
        for i in range(mn):
            t = i / SR
            env = math.sin(math.pi * (t / 1.6))
            f = 90 + 30 * math.sin(t * 3)
            seg.append((0.5 * math.sin(2 * math.pi * f * t)
                        + 0.3 * random.uniform(-1, 1)) * env)
        seg = lowpass(seg, 800)
        start = int(at * SR)
        for i, sm in enumerate(seg):
            j = start + i
            if 0 <= j < n:
                p = i / mn
                left[j] += sm * 0.12 * (1.0 - p)
                right[j] += sm * 0.12 * p
    moto(4.0); moto(9.5)
    # normalize jointly
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right), 1e-9)
    g = 0.7 / peak
    stereo = [(left[i] * g, right[i] * g) for i in range(n)]
    save("ambience_night.wav", stereo, folder=MUSIC_DIR, stereo=True, peak=0.7)

def ambience_dread():
    # tenser ambience for late nights: lower drone + heartbeat-ish pulse + wind
    dur = 14.0
    n = int(SR * dur)
    left = [0.0] * n
    right = [0.0] * n
    for i in range(n):
        t = i / SR
        d = (0.5 * math.sin(2 * math.pi * 41 * t)
             + 0.4 * math.sin(2 * math.pi * 41.5 * t)
             + 0.25 * math.sin(2 * math.pi * 82 * t))
        wind = 0.15 * (random.uniform(-1, 1))
        v = d * 0.13 + 0.0
        left[i] += v
        right[i] += v * 0.96
    # filtered wind layer
    wind = bandpass(noise(dur), 200, 1400)
    for i in range(n):
        t = i / SR
        env = 0.06 * (0.6 + 0.4 * math.sin(t * 0.4))
        left[i] += wind[i] * env
        right[i] += wind[i] * env * 0.9
    # slow ominous pulses
    tt = 0.0
    while tt < dur:
        pul = exp_decay(sine(48, 0.6), 0.2)
        start = int(tt * SR)
        for i, sm in enumerate(pul):
            j = start + i
            if 0 <= j < n:
                left[j] += sm * 0.25
                right[j] += sm * 0.25
        tt += 2.6
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right), 1e-9)
    g = 0.7 / peak
    stereo = [(left[i] * g, right[i] * g) for i in range(n)]
    save("ambience_dread.wav", stereo, folder=MUSIC_DIR, stereo=True, peak=0.7)

# ---------------------------------------------------------------- run
if __name__ == "__main__":
    print("Generating SFX ...")
    ui_click(); ui_hover(); ui_back(); ui_confirm()
    clock_tick(); clock_chime()
    door_slam(); door_creak(); light_switch(); fluorescent_hum()
    camera_switch(); static_loop(); camera_up(); camera_down()
    heartbeat(); breathing(); whisper()
    stinger(); power_down(); low_power_beep()
    offering_bell(); incense_whoosh(); item_good(); item_bad()
    footstep_wood(); knock(); rooster(); vendor_bell()
    print("Generating jumpscare ...")
    jumpscare()
    print("Generating ambience (this takes a moment) ...")
    ambience_night(); ambience_dread()
    print("Done.")
