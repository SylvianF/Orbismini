"""Orbiscan dans Orbismini : passage entre le téléphone et le relais du PC du magasin.

Le relais de chaque PC (Dropbox\\ScannerGtaX\\relais, module orbiscan_nuage.py) garde une ligne
ouverte vers Orbismini : il vient chercher les demandes du téléphone, les rejoue sur lui-même
(127.0.0.1:8790) et renvoie la réponse. Le téléphone voit donc exactement la page Orbiscan du PC.

Règles (vérifiées par tests/test_orbiscan.py) :
  - tout reste en mémoire vive : rien n'est jamais écrit sur disque ni dans les journaux ;
  - une photo ne passe que chiffrée sur le téléphone avec la clé publique du PC
    (RSA-OAEP 2048 + AES-256-GCM) : Orbismini ne peut pas la lire et refuse toute photo en clair ;
  - chaque demande est effacée dès que le relais l'a prise, chaque réponse dès que le téléphone
    l'a lue, et tout ce qui traîne disparaît au bout de 2 minutes au plus ;
  - le téléphone ne voit que les PC qui sortent sur internet par la même connexion que lui
    (même adresse IPv4, ou même réseau IPv6 /64) : hors du Wi-Fi du magasin, rien ;
  - seules les adresses de la page du téléphone passent (liste fermée) : jamais celles réservées
    au scanner GtaX ni à Orbis sur le PC.
"""

import base64
import hashlib
import hmac
import ipaddress
import re
import secrets
import threading
import time
from collections import deque

PC_TTL = 30            # secondes sans relève : PC hors ligne
RELAY_WAIT = 20        # secondes : attente du relais (ligne ouverte) avant de répondre « rien »
PHONE_WAIT = 15        # secondes : attente de la réponse du PC pour le téléphone
KEEP = 120             # secondes : tout ce qui n'a pas été pris est effacé
MAX_BODY = 20 * 1024 * 1024
MAX_TOTAL = 80 * 1024 * 1024
MAX_PCS = 60
SEALED = "application/x-orbiscan-chiffre"
MAGIC = b"OSC1"

TOKEN = r"[\w-]{10,64}"
# Adresses de la page du téléphone (et elles seules) : méthode, chemin.
ALLOWED = [
    ("GET", re.compile(r"/t")),
    ("GET", re.compile(r"/p/%s" % TOKEN)),
    ("GET", re.compile(r"/[\w-]+\.png")),
    ("GET", re.compile(r"/api/ping")),
    ("GET", re.compile(r"/api/next/%s" % TOKEN)),
    ("GET", re.compile(r"/api/status/%s" % TOKEN)),
    ("POST", re.compile(r"/api/pair-code")),
    ("POST", re.compile(r"/api/pair/%s" % TOKEN)),
    ("POST", re.compile(r"/api/upload/%s/(recto|verso|rib|face|revers|facture)" % TOKEN)),
    ("POST", re.compile(r"/api/done/%s" % TOKEN)),
]
UPLOAD = re.compile(r"/api/upload/")


def allowed(method, path):
    return any(m == method and rx.fullmatch(path) for m, rx in ALLOWED)


def same_network(a, b):
    """Même sortie sur internet : même IPv4, ou même /64 en IPv6."""
    try:
        x, y = ipaddress.ip_address(a), ipaddress.ip_address(b)
    except ValueError:
        return False
    if x.version != y.version:
        return False
    if x.version == 4:
        return x == y
    return ipaddress.ip_network(f"{x}/64", strict=False) == ipaddress.ip_network(f"{y}/64", strict=False)


def valid_key(key):
    """Clé publique RSA du PC : {"n": base64url, "e": base64url}, 2048 bits ou plus."""
    try:
        n = base64.urlsafe_b64decode(key["n"] + "==")
        e = base64.urlsafe_b64decode(key["e"] + "==")
        return len(n) >= 256 and 0 < len(e) <= 8
    except (KeyError, TypeError, ValueError):
        return False


class Tunnel:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.lock = threading.Condition()
        self.pcs = {}        # id → {name, key, secret, ip, seen, queue}
        self.calls = {}      # numéro → {pc, method, path, ctype, body, at, answer}

    # ---------------------------------------------------------------- ménage
    def _purge(self):
        now = self.clock()
        for rid in [r for r, c in self.calls.items() if now - c["at"] > KEEP]:
            del self.calls[rid]
        for pc in [p for p, x in self.pcs.items() if now - x["seen"] > KEEP]:
            del self.pcs[pc]

    def _held(self):
        return sum(len(c["body"] or b"") + len((c["answer"] or {}).get("body") or b"") for c in self.calls.values())

    def _online(self, x):
        return self.clock() - x["seen"] < PC_TTL or x["waiting"]

    # ---------------------------------------------------------------- relais du PC
    def relay_wait(self, pc, name, key, secret, ip, wait=RELAY_WAIT):
        """Ligne ouverte du relais : rend les demandes du téléphone dès qu'il y en a."""
        if not re.fullmatch(r"[\w-]{8,40}", str(pc or "")) or not valid_key(key) or len(str(secret or "")) < 20:
            raise PermissionError("relais invalide")
        digest = hashlib.sha256(str(secret).encode()).hexdigest()
        with self.lock:
            self._purge()
            x = self.pcs.get(pc)
            if x and not hmac.compare_digest(x["secret"], digest) and self._online(x):
                raise PermissionError("PC déjà relié par un autre relais")
            if not x and len(self.pcs) >= MAX_PCS:
                raise PermissionError("trop de PC")
            if not x or x["secret"] != digest:
                x = self.pcs[pc] = dict(queue=deque(), waiting=0)
            x.update(name=str(name or pc)[:40], key={"n": key["n"], "e": key["e"]}, secret=digest, ip=ip, seen=self.clock())
            x["waiting"] += 1
            try:
                end = self.clock() + wait
                while not x["queue"] and self.clock() < end and self.pcs.get(pc) is x:
                    self.lock.wait(min(1.0, max(0.0, end - self.clock())))
                out = []
                while x["queue"]:
                    rid = x["queue"].popleft()
                    c = self.calls.get(rid)
                    if not c:
                        continue
                    body, c["body"] = c["body"], None      # la demande quitte Orbismini
                    out.append(dict(id=rid, method=c["method"], path=c["path"], type=c["ctype"],
                                    body=base64.b64encode(body or b"").decode()))
                return out
            finally:
                x["waiting"] -= 1
                x["seen"] = self.clock()

    def relay_answer(self, pc, secret, rid, status, ctype, body):
        digest = hashlib.sha256(str(secret).encode()).hexdigest()
        with self.lock:
            x = self.pcs.get(pc)
            c = self.calls.get(rid)
            if not x or not hmac.compare_digest(x["secret"], digest) or not c or c["pc"] != pc:
                raise PermissionError("réponse inconnue")
            if len(body) > MAX_BODY:
                status, ctype, body = 502, "application/json", b'{"error": "r\\u00e9ponse trop lourde"}'
            c["answer"] = dict(status=int(status), ctype=str(ctype or "application/octet-stream")[:100], body=body)
            x["seen"] = self.clock()
            self.lock.notify_all()

    # ---------------------------------------------------------------- téléphone
    def peers(self, ip):
        """PC du magasin vus depuis ce téléphone (même connexion), du plus ancien nom au plus récent."""
        with self.lock:
            self._purge()
            found = [dict(pc=p, name=x["name"], key=x["key"], url="/api/orbiscan/pc/" + p)
                     for p, x in self.pcs.items() if self._online(x) and same_network(ip, x["ip"])]
        return sorted(found, key=lambda p: (p["name"].lower(), p["pc"]))

    def call(self, ip, pc, method, path, ctype="", body=b"", wait=PHONE_WAIT):
        """Demande du téléphone au PC : (statut, type, contenu)."""
        if not allowed(method, path):
            return 403, "application/json", b'{"error": "adresse interdite"}'
        if UPLOAD.match(path) and (ctype != SEALED or not body.startswith(MAGIC)):
            return 415, "application/json", b'{"error": "photo non chiffr\\u00e9e refus\\u00e9e"}'
        if len(body) > MAX_BODY:
            return 413, "application/json", b'{"error": "trop lourd"}'
        with self.lock:
            self._purge()
            x = self.pcs.get(pc)
            if not x or not self._online(x) or not same_network(ip, x["ip"]):
                return 404, "application/json", b'{"error": "PC introuvable sur ce r\\u00e9seau"}'
            if self._held() + len(body) > MAX_TOTAL:
                return 503, "application/json", b'{"error": "occup\\u00e9, r\\u00e9essaie"}'
            rid = secrets.token_urlsafe(12)
            c = self.calls[rid] = dict(pc=pc, method=method, path=path, ctype=str(ctype or "")[:100],
                                       body=body, at=self.clock(), answer=None)
            x["queue"].append(rid)
            self.lock.notify_all()
            end = self.clock() + wait
            while c["answer"] is None and self.clock() < end:
                self.lock.wait(min(1.0, max(0.0, end - self.clock())))
            self.calls.pop(rid, None)                   # réponse lue (ou abandonnée) : effacée
            if x["queue"] and rid in x["queue"]:
                x["queue"].remove(rid)
            a = c["answer"]
        if a is None:
            return 504, "application/json", b'{"error": "le PC ne r\\u00e9pond pas"}'
        return a["status"], a["ctype"], a["body"]

    def held_bytes(self):
        with self.lock:
            return self._held()


TUNNEL = Tunnel()


def page(html, home):
    """Page Orbiscan du PC, servie dans Orbismini : ses fichiers sous /orbiscan/, et le raccord
    (orbiscan-shim.js) chargé avant son propre code."""
    import json

    head = ('<head><script>window.ORBISCAN_HOME = ' + json.dumps(home) + ';</script>'
            '<script src="/orbiscan-shim.js"></script>')
    html = html.replace('href="/', 'href="/orbiscan/').replace('src="/', 'src="/orbiscan/')
    return html.replace("<head>", head, 1)


NO_PC_PAGE = """<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<meta http-equiv="refresh" content="5">
<title>Orbiscan</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; flex-direction: column; background: #f5f5f7; color: #222;
    font: 17px/1.4 -apple-system, "Segoe UI", Roboto, Arial, sans-serif; }
  header { background: #fff; padding: 14px 16px; text-align: center; border-bottom: 1px solid #ddd; }
  h1 { margin: 0; font-size: 22px; font-weight: 600; color: #8a6d1d; }
  h1 span { color: #8a8f96; font-weight: 500; font-size: 17px; }
  main { padding: 16px; max-width: 520px; width: 100%; margin: 0 auto; box-sizing: border-box; }
  .expired { text-align: center; background: #fdecec; color: #b00; border-radius: 12px; padding: 22px 16px;
    font-weight: 600; font-size: 18px; }
  .expired small { display: block; font-weight: 400; margin-top: 6px; font-size: 15px; }
  .old { text-align: center; color: #666; font-size: 15px; margin-top: 22px; }
  .old a { color: #b71f4d; font-weight: 600; }
</style></head>
<body><header><h1>Orbis<span>(can)</span></h1></header>
<main><div class="expired">Aucun PC Orbis sur ce réseau
<small>Orbiscan ne marche que sur le Wi-Fi du magasin, PC allumé.<br>La page réessaie toute seule.</small></div>
<p class="old">PC pas encore mis à jour ?<br><a href="http://orbiscan.local:8790/t" target="_blank" rel="noopener">Ouvrir l’Orbiscan du PC par le Wi-Fi</a></p></main>
</body></html>
"""
