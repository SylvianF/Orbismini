"""Son d'Orbis à l'arrivée d'une demande de virement (virements_panel.js, chime), rendu en
fichier WAV : trois notes montantes en onde triangulaire, même enveloppe que dans Orbis.
Seul le volume change : dans Orbis le son est joué bas (0,09) ; le fichier est porté à
-3 dB pour servir de son de notification."""
import math
import struct
import sys
import wave

RATE = 44100
NOTES = [(784, 0.0, 0.16), (988, 0.16, 0.16), (1319, 0.32, 0.32)]  # fréquence, début, durée (s)
ATTACK, FLOOR, PEAK, TAIL = 0.02, 0.0001, 0.09, 0.02


def triangle(freq, t):
    """Onde triangulaire sans repliement : harmoniques impairs sous la moitié de RATE."""
    out, k = 0.0, 0
    while (2 * k + 1) * freq < RATE / 2:
        n = 2 * k + 1
        out += (-1) ** k * math.sin(2 * math.pi * n * freq * t) / (n * n)
        k += 1
    return out * 8 / math.pi**2


def envelope(t, length):
    """Montée linéaire en 20 ms, puis descente exponentielle jusqu'à la fin de la note."""
    if t < 0 or t > length + TAIL:
        return 0.0
    if t < ATTACK:
        return FLOOR + (PEAK - FLOOR) * t / ATTACK
    if t < length:
        return PEAK * (FLOOR / PEAK) ** ((t - ATTACK) / (length - ATTACK))
    return FLOOR


total = max(start + length for _, start, length in NOTES) + 0.1
samples = []
for i in range(int(total * RATE)):
    t = i / RATE
    samples.append(sum(triangle(f, t - start) * envelope(t - start, length) for f, start, length in NOTES))
gain = 10 ** (-3 / 20) / max(abs(s) for s in samples)
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", round(s * gain * 32767)) for s in samples))
print("%.2f s, %d échantillons" % (total, len(samples)))
