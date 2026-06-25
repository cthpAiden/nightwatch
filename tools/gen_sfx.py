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
    save("jumpscare.wav", soft_clip(out), folder=JUMP_DIR, peak=0.9)

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

def candle_gust():
    # a cold draft snuffing the altar candles. Now leads with a sharp INHALED-breath
    # transient (something drew the air in) before the low fwoomp, so it reads as a
    # presence blowing the candles out, not just wind.
    s = buf(0.8)
    br = bandpass(noise(0.2), 380, 2600)
    bsh = []
    for i, x in enumerate(br):
        t = i / SR
        env = (t / 0.04) if t < 0.04 else max(0.0, 1.0 - (t - 0.04) / 0.16)  # fast in, quick out
        bsh.append(x * env)
    add(s, bsh, 0.0, 0.8)
    g = bandpass(noise(0.45), 200, 1900)
    sh = []
    for i, x in enumerate(g):
        t = i / SR
        env = math.sin(math.pi * min(1.0, t / 0.45))
        sh.append(x * env)
    add(s, sh, 0.18, 0.75)
    add(s, exp_decay(sine(85, 0.24), 0.05), 0.46, 0.45)
    save("candle_gust.wav", soft_clip(s), peak=0.55)

def phone_ring():
    # an old desk phone: two bursts of a 440+480 Hz tone, chopped by a ~20 Hz ringer
    n = int(SR * 1.4)
    out = []
    for i in range(n):
        t = i / SR
        burst = 1.0 if (t < 0.4 or (0.6 < t < 1.0)) else 0.0
        warble = 1.0 if math.sin(2 * math.pi * 20 * t) > 0 else 0.25
        v = (math.sin(2 * math.pi * 440 * t) + math.sin(2 * math.pi * 480 * t)) * 0.5
        out.append(v * burst * warble)
    save("phone_ring.wav", soft_clip(out), peak=0.5)

def phone_ring_warp():
    # the SAME phone, but WRONG — lower, detuned, sagging pitch, slower ringer, plus
    # tape wow/flutter, a broken-intercom bitcrush, and a reversed whisper bed so
    # something is clearly "on the line". The tell that it's Ma da imitating the call.
    n = int(SR * 1.6)
    out = []
    for i in range(n):
        t = i / SR
        wow = 1.0 + 0.012 * math.sin(2 * math.pi * 3.0 * t)   # slow tape wow
        burst = 1.0 if (t < 0.5 or (0.8 < t < 1.4)) else 0.0
        warble = 1.0 if math.sin(2 * math.pi * 11 * t) > 0 else 0.3
        bend = 1.0 - 0.1 * t          # the pitch sags as it rings
        v = (math.sin(2 * math.pi * 300 * bend * wow * t)
             + math.sin(2 * math.pi * 317 * bend * wow * t)) * 0.5
        out.append(v * burst * warble)
    out = lowpass(out, 1500)
    out = [round(v * 16) / 16 for v in out]                   # ~4-bit bitcrush grit
    wh = bandpass(noise(1.6), 700, 3000)
    wh = adsr(wh, a=0.3, d=0.2, s=0.6, r=0.6)
    wh = wh[::-1]                                              # reversed whisper bed
    for i in range(min(len(out), len(wh))):
        out[i] += wh[i] * 0.12
    save("phone_ring_warp.wav", soft_clip(out), peak=0.5)

# ---------------------------------------------------------------- tension bed
def drone_tension():
    # A low, detuned, slowly-breathing drone faded in when a threat is at the door or
    # vía is critical. Built to loop seamlessly: the 0.5 Hz tremolo completes exactly
    # two cycles over 4.0 s, and there is no fade in/out, so the loop point is silent.
    dur = 4.0
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        lfo = 0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * t)   # 2 full cycles in 4 s
        v = (math.sin(2 * math.pi * 55.0 * t)
             + 0.7 * math.sin(2 * math.pi * 55.5 * t)        # detune -> slow beating; 55.5*4=222 whole cycles (seamless loop)
             + 0.5 * math.sin(2 * math.pi * 82.5 * t)
             + 0.35 * math.sin(2 * math.pi * 110.0 * t))
        out.append(v * (0.5 + 0.5 * lfo))
    out = lowpass(out, 600)
    save("drone_tension.wav", out, peak=0.5)

def coin_chime():
    # A soft two-note ding for earning vàng mã.
    s = buf(0.4)
    add(s, exp_decay(sine(1180, 0.25), 0.10), 0.0, 0.5)
    add(s, exp_decay(sine(1760, 0.30), 0.12), 0.05, 0.4)
    save("coin_chime.wav", s, peak=0.4)

# ---------------------------------------------------------------- ambience (stereo)
def _cricket(left, right, n, at, freq, pan, gain):
    # one cricket chirp (short trilled high tone), panned, summed into L/R
    cn = int(SR * 0.12)
    start = int(at * SR)
    for i in range(cn):
        j = start + i
        if not (0 <= j < n):
            continue
        t = i / SR
        trill = 1.0 if (math.sin(t * 2 * math.pi * 38) > 0) else 0.18
        env = math.sin(math.pi * (t / 0.12))
        sm = math.sin(2 * math.pi * freq * t) * env * trill
        left[j] += sm * gain * (1.0 - pan)
        right[j] += sm * gain * pan

def _cricket_bed(dur, gap_lo, gap_hi, f_lo, f_hi, gain):
    n = int(SR * dur)
    left = [0.0] * n
    right = [0.0] * n
    tt = 0.0
    while tt < dur:
        _cricket(left, right, n, tt, random.uniform(f_lo, f_hi), random.random(), gain)
        tt += random.uniform(gap_lo, gap_hi)
    # very faint airy bed so it isn't dead silence between chirps
    air = lowpass(noise(dur), 900)
    for i in range(n):
        left[i] += air[i] * 0.012
        right[i] += air[i] * 0.012
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right), 1e-9)
    g = 0.7 / peak
    return [(left[i] * g, right[i] * g) for i in range(n)]

def ambience_night():
    # Calm night: a lively, dense cricket bed (no drone/wind/traffic — those read
    # as a bug). Just crickets, per the brief.
    stereo = _cricket_bed(14.0, 0.10, 0.30, 3600, 5200, 0.22)
    save("ambience_night.wav", stereo, folder=MUSIC_DIR, stereo=True, peak=0.7)

def ambience_dread():
    # Late nights: the same crickets, sparser and a touch lower — tenser, but
    # still just crickets (no wind/drone).
    stereo = _cricket_bed(14.0, 0.30, 0.75, 3000, 4400, 0.20)
    save("ambience_dread.wav", stereo, folder=MUSIC_DIR, stereo=True, peak=0.7)

# ---------------------------------------------------------------- horror: anticipation + body
def pre_scare():
    # The held breath BEFORE a jumpscare image: a rising sub swell + an air "inhale"
    # that pulls inward, so the half-second of dread is felt, not just heard.
    dur = 0.6
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = 38.0 + 26.0 * (t / dur)          # 38 -> 64 Hz climb
        amp = (t / dur) ** 1.5               # swell in
        out.append(math.sin(2 * math.pi * f * t) * amp)
    air = bandpass(noise(dur), 200, 1700)
    for i in range(n):
        t = i / SR
        out[i] += air[i] * ((t / dur) ** 2) * 0.4
    out = lowpass(out, 800)
    save("pre_scare.wav", soft_clip(out), peak=0.85)

def ambience_sub():
    # A continuous, near-subliminal sub-bass dread floor (felt, not heard). Two close
    # sines (slow beating) under a slow amp LFO. Freqs chosen for a seamless 8 s loop.
    dur = 8.0
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        lfo = 0.62 + 0.38 * math.sin(2 * math.pi * 0.125 * t)   # 1 cycle / 8 s
        v = (math.sin(2 * math.pi * 36.0 * t)                    # 288 whole cycles
             + 0.7 * math.sin(2 * math.pi * 36.5 * t))           # 292 whole cycles
        out.append(v * lfo)
    save("ambience_sub.wav", out, peak=0.14)

# ---------------------------------------------------------------- per-threat approaches
def approach_drag():
    # Quỷ nhập tràng: a slow, wet drag/shuffle with irregular dragging thuds.
    dur = 1.5
    s = buf(dur)
    drag = lowpass(noise(dur), 340)
    sh = []
    for i, x in enumerate(drag):
        t = i / SR
        env = 0.45 + 0.55 * max(0.0, math.sin(2 * math.pi * 1.25 * t))
        sh.append(x * env)
    add(s, sh, 0.0, 0.7)
    for at in (0.18, 0.66, 1.12):
        add(s, exp_decay(sine(68, 0.2), 0.05), at, 0.6)
    save("approach_drag.wav", soft_clip(s), peak=0.7)

def approach_heavy():
    # Ông kẹ: three heavy, DESCENDING knocks — slow and certain.
    s = buf(1.6)
    def k(at, f, g):
        imp = exp_decay(sine(f, 0.18), 0.03)
        imp = add(imp, exp_decay(bandpass(noise(0.12), 120, 1800), 0.018), gain=0.6)
        add(s, imp, at, g)
    k(0.0, 150, 1.0); k(0.52, 120, 0.95); k(1.04, 92, 0.9)
    save("approach_heavy.wav", soft_clip(s), peak=0.85)

def approach_soft():
    # The rest: a small, childlike single tap from the dark — almost shy.
    s = buf(0.5)
    add(s, exp_decay(sine(300, 0.1), 0.02), 0.0, 0.55)
    add(s, exp_decay(bandpass(noise(0.06), 400, 3000), 0.01), 0.0, 0.4)
    save("approach_soft.wav", s, peak=0.4)

# ---------------------------------------------------------------- ma da water
def water_loop():
    # A continuous body of water: low gurgle under a slow swell, lapping wash, sparse
    # drips. The amp dips toward the loop seam so the 4 s loop is clickless.
    dur = 4.0
    n = int(SR * dur)
    base = lowpass(noise(dur), 250)
    wash = bandpass(noise(dur), 200, 800)
    out = []
    for i in range(n):
        t = i / SR
        seam = 0.5 - 0.5 * math.cos(2 * math.pi * (t / dur))    # 0 at seams, 1 mid
        lfo = 0.6 + 0.4 * math.sin(2 * math.pi * 0.25 * t)
        v = base[i] * lfo * 0.7
        v += wash[i] * 0.18 * (0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * t))
        out.append(v * (0.25 + 0.75 * seam))
    for at in (0.35, 1.2, 2.1, 3.25):
        add(out, exp_decay(sine(880, 0.05), 0.012), at, 0.22)
    save("water_loop.wav", out, peak=0.42)

def water_call():
    # Ma da's lure: a drowned, almost-worded cry — low filtered whisper + a wavering
    # sung vowel + faint gurgle. "Help me..." you can't quite make out.
    dur = 1.8
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        mod = 0.5 + 0.5 * abs(math.sin(t * 4.0))
        out.append(random.uniform(-1, 1) * mod)
    out = bandpass(out, 380, 1700)
    out = adsr(out, a=0.3, d=0.2, s=0.6, r=0.5)
    for i in range(n):
        t = i / SR
        f = 220.0 * (1.0 - 0.05 * math.sin(2 * math.pi * 3 * t))
        v = 0.0
        for h, g in [(1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)]:
            v += g * math.sin(2 * math.pi * f * h * t)
        env = math.sin(math.pi * min(1.0, t / dur))
        out[i] += v * env * 0.16
    gur = lowpass(noise(dur), 250)
    for i in range(n):
        out[i] += gur[i] * 0.18
    save("water_call.wav", soft_clip(out), peak=0.4)

# ---------------------------------------------------------------- stinger family
def sting_low():
    # the original low dread hit (door arrival).
    s = buf(1.0)
    add(s, exp_decay(sine(110, 0.8), 0.3), 0.0, 1.0)
    add(s, exp_decay(sine(165, 0.8), 0.25), 0.0, 0.4)
    add(s, exp_decay(bandpass(noise(0.5), 300, 4000), 0.1), 0.0, 0.5)
    save("sting_low.wav", soft_clip(s), peak=0.85)

def sting_rise():
    # "you took the bait" — an upward sweep (ma da lure answered / fake phone).
    dur = 0.7
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        f = 120.0 + 640.0 * (t / dur) ** 2
        out.append(math.sin(2 * math.pi * f * t))
    out = adsr(out, a=0.005, d=0.05, s=0.7, r=0.2)
    out = add(out, exp_decay(bandpass(noise(0.4), 500, 5000), 0.12), gain=0.4)
    save("sting_rise.wav", soft_clip(out), peak=0.7)

def sting_metal():
    # an inharmonic metallic cluster — the risen corpse (quỷ nhập tràng).
    s = buf(1.0)
    base = 180
    for mult, g, tau in [(1.0, 1.0, 0.5), (2.41, 0.6, 0.4), (3.83, 0.4, 0.3), (5.2, 0.25, 0.2)]:
        add(s, exp_decay(sine(base * mult, 1.0), tau), 0.0, g)
    add(s, exp_decay(bandpass(noise(0.3), 800, 6000), 0.05), 0.0, 0.4)
    save("sting_metal.wav", soft_clip(s), peak=0.7)

def sting_breath():
    # a sharp, sudden inhaled gasp — candle gutter / oan hồn's quiet grab.
    dur = 0.8
    out = bandpass(noise(dur), 300, 2200)
    sh = []
    for i, x in enumerate(out):
        t = i / SR
        env = (t / 0.1) if t < 0.1 else max(0.0, 1.0 - (t - 0.1) / 0.5)
        sh.append(x * env)
    add(sh, exp_decay(sine(70, 0.3), 0.08), 0.0, 0.3)
    save("sting_breath.wav", soft_clip(sh), peak=0.5)

# ---------------------------------------------------------------- door-strain + altar bed
def shutter_strain():
    # The far side of a CLOSED shutter when something is pressing it: a low detuned
    # groan with an intermittent metal creak. Seam-masked 4 s loop.
    dur = 4.0
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        seam = 0.5 - 0.5 * math.cos(2 * math.pi * (t / dur))
        v = (math.sin(2 * math.pi * 80 * t) + 0.7 * math.sin(2 * math.pi * 83 * t))
        out.append(v * 0.5 * seam)
    creak = bandpass(noise(dur), 600, 2400)
    for i in range(n):
        t = i / SR
        cm = max(0.0, math.sin(2 * math.pi * 0.5 * t)) ** 3
        seam = 0.5 - 0.5 * math.cos(2 * math.pi * (t / dur))
        out[i] += creak[i] * cm * 0.3 * seam
    save("shutter_strain.wav", out, peak=0.4)

def incense_bed():
    # A near-subliminal soft crackle while the altar burns — warmth you can feel
    # slipping away when it guts out. Seam-masked 4 s loop.
    dur = 4.0
    n = int(SR * dur)
    cr = bandpass(noise(dur), 1200, 5000)
    out = []
    for i in range(n):
        t = i / SR
        seam = 0.5 - 0.5 * math.cos(2 * math.pi * (t / dur))
        gate = 1.0 if random.random() < 0.02 else 0.04
        out.append(cr[i] * gate * seam)
    out = lowpass(out, 6000)
    save("incense_bed.wav", out, peak=0.1)

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
    candle_gust(); phone_ring(); phone_ring_warp()
    drone_tension(); coin_chime()
    print("Generating horror cues ...")
    pre_scare(); ambience_sub()
    approach_drag(); approach_heavy(); approach_soft()
    water_loop(); water_call()
    sting_low(); sting_rise(); sting_metal(); sting_breath()
    shutter_strain(); incense_bed()
    print("Generating jumpscare ...")
    jumpscare()
    print("Generating ambience (this takes a moment) ...")
    ambience_night(); ambience_dread()
    print("Done.")
