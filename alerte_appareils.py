"""Alerte de cours propre à chaque téléphone (en plus de l’alerte commune avec Orbis, alerte.py).

Chaque téléphone tire au hasard, à sa première ouverture, un identifiant secret gardé sur lui
(localStorage « orbismini-appareil ») et l’envoie avec chaque demande (en-tête X-Appareil). Il a ses
propres seuils et son propre canal ntfy : les autres téléphones ne les voient pas, ne les changent
pas et ne reçoivent pas ses alertes.

Un téléphone peut être relié à l’alerte commune avec Orbis, avec le code de Sylvian
(ORBISCAN_ADMIN, le même que pour la page des PC d’Orbiscan) : il voit et règle alors l’alerte
d’Orbis, comme avant.

Où : fichier alertes.json de la branche « alertes » du dépôt d’Orbismini (comme pc.json d’Orbiscan,
Render ne redémarre pas quand il change). Le dépôt peut être lu par d’autres : il n’y a que
l’empreinte de l’identifiant de chaque téléphone (jamais l’identifiant), ses seuils et ses
dernières alertes. Le canal ntfy n’y est pas : il est calculé à partir de l’empreinte et d’une clé
tirée du mot de passe d’Orbismini (réglages de Render), donc introuvable depuis le dépôt."""

import base64
import hashlib
import hmac
import json
import os
import re
import threading
import time
from datetime import datetime, timezone

import alerte
import orbiscan_pc

BRANCH = "alertes"
FILE = "alertes.json"
MAX_DEVICES = 200
FORGET_DAYS = 90       # téléphone sans alerte en place ni visite depuis 90 jours : oublié
SECRET = re.compile(r"[0-9a-f]{32}")


def device_id(secret):
    """Empreinte de l’identifiant du téléphone (seule gardée) ; None s’il n’est pas valable."""
    secret = str(secret or "").strip().lower()
    if not SECRET.fullmatch(secret):
        return None
    return hashlib.sha256(("orbismini-appareil:" + secret).encode()).hexdigest()


def _channel_key():
    password = os.environ.get("GOLDAPP_PASSWORD", "")
    return hashlib.sha256(("orbismini-canal:" + password).encode()).digest()


def channel(did):
    """Canal ntfy du téléphone : introuvable sans le mot de passe d’Orbismini."""
    return "orbismini-" + hmac.new(_channel_key(), did.encode(), hashlib.sha256).hexdigest()[:20]


def _today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


class Store:
    def __init__(self, token=None):
        self.token = os.environ.get("ORBISCAN_GITHUB_TOKEN", "").strip() if token is None else token
        self.lock = threading.RLock()
        self.data = None     # {"devices": {id: {state, seen}}, "orbis": [id, …]}
        self.sha = None
        self.sent = set()
        self.checked = 0.0

    # ---------------------------------------------------------------- GitHub
    def _url(self, path):
        return f"{orbiscan_pc.API}/repos/{orbiscan_pc.REPO}/{path}"

    def _load(self):
        if self.data is not None:
            return
        if not self.token:
            raise PermissionError("Alertes par téléphone indisponibles (ORBISCAN_GITHUB_TOKEN absent)")
        status, out = orbiscan_pc.http("GET", self._url(f"contents/{FILE}?ref={BRANCH}"), self.token)
        if status == 200:
            data = json.loads(base64.b64decode(out["content"]))
            self.sha = out["sha"]
        elif status == 404:
            data, self.sha = {}, None
        else:
            raise PermissionError("Alertes illisibles pour l’instant, réessaie dans une minute (GitHub %s)" % status)
        self.data = dict(devices=dict(data.get("devices") or {}), orbis=list(data.get("orbis") or []))
        # Alertes déjà connues au démarrage : pas renvoyées.
        self.sent.update(h["id"] for d in self.data["devices"].values() for h in d["state"].get("hits") or [])

    def _branch(self):
        status, _ = orbiscan_pc.http("GET", self._url(f"git/ref/heads/{BRANCH}"), self.token)
        if status == 200:
            return
        status, main = orbiscan_pc.http("GET", self._url("git/ref/heads/main"), self.token)
        if status != 200:
            raise PermissionError("dépôt inaccessible (GitHub %s)" % status)
        status, _ = orbiscan_pc.http("POST", self._url("git/refs"), self.token,
                                     {"ref": "refs/heads/" + BRANCH, "sha": main["object"]["sha"]})
        if status not in (201, 422):
            raise PermissionError("branche impossible à créer (GitHub %s)" % status)

    def _save(self, data, message):
        if self.sha is None:
            self._branch()
        body = {"message": message, "branch": BRANCH,
                "content": base64.b64encode(json.dumps(data, indent=1, sort_keys=True, ensure_ascii=False).encode()).decode()}
        if self.sha:
            body["sha"] = self.sha
        status, out = orbiscan_pc.http("PUT", self._url(f"contents/{FILE}"), self.token, body)
        if status not in (200, 201):
            self.data = None             # relire au prochain passage
            raise PermissionError("Alerte non enregistrée, réessaie dans une minute (GitHub %s)" % status)
        self.sha, self.data = out["content"]["sha"], data

    def _copy(self):
        return json.loads(json.dumps(self.data))

    def _prune(self, data):
        limit = datetime.fromtimestamp(time.time() - FORGET_DAYS * 86400, timezone.utc).strftime("%Y-%m-%d")
        for did, d in list(data["devices"].items()):
            s = d["state"]
            if not (s.get("above") or s.get("below") or s.get("move")) and d.get("seen", "") < limit:
                del data["devices"][did]

    # ---------------------------------------------------------------- téléphone
    def linked(self, did):
        """Vrai si ce téléphone est relié à l’alerte commune avec Orbis."""
        with self.lock:
            self._load()
            return did in self.data["orbis"]

    def view(self, did):
        with self.lock:
            self._load()
            d = self.data["devices"].get(did)
            out = json.loads(json.dumps(d["state"])) if d else {"hits": []}
        out["channel"] = channel(did)
        return out

    def update(self, did, theirs):
        """Nouveaux réglages de ce téléphone (le plus récent l’emporte)."""
        theirs = alerte.clean(theirs)
        with self.lock:
            self._load()
            data = self._copy()
            d = data["devices"].get(did)
            if not d:
                self._prune(data)
                if len(data["devices"]) >= MAX_DEVICES:
                    raise PermissionError("Trop de téléphones avec une alerte")
                d = data["devices"][did] = dict(state={"hits": []})
            d["state"] = alerte.merge(d["state"], dict(theirs, hits=[]))
            d["seen"] = _today()
            if d["state"] != (self.data["devices"].get(did) or {}).get("state"):
                self._save(data, "Alerte de cours d’un téléphone")
        return self.view(did)

    def link(self, did, code):
        if not orbiscan_pc.STORE.admin_ok(code):
            raise PermissionError("Code incorrect")
        with self.lock:
            self._load()
            if did not in self.data["orbis"]:
                data = self._copy()
                data["orbis"].append(did)
                self._save(data, "Téléphone relié à l’alerte d’Orbis")

    def unlink(self, did):
        with self.lock:
            self._load()
            if did in self.data["orbis"]:
                data = self._copy()
                data["orbis"].remove(did)
                self._save(data, "Téléphone détaché de l’alerte d’Orbis")

    # ---------------------------------------------------------------- contrôle
    def check(self, price_loader, post=None):
        """Contrôle du cours pour tous les téléphones (au plus une fois par minute)."""
        if time.monotonic() - self.checked < 60:
            return []
        self.checked = time.monotonic()
        with self.lock:
            self._load()
            if not any(d["state"].get(k) for d in self.data["devices"].values() for k in alerte.SETTINGS):
                return []
            got = price_loader()
            data, hits = self._copy(), []
            for did, d in data["devices"].items():
                hit = alerte.apply_price(d["state"], got[0], got[1], got[2] if len(got) > 2 else None)
                if hit:
                    hits.append((did, hit))
            if hits:
                self._save(data, "Alerte de cours sonnée (%d téléphone%s)" % (len(hits), "s" if len(hits) > 1 else ""))
        out = []
        for did, h in hits:
            if h["id"] in self.sent:
                continue
            self.sent.add(h["id"])
            try:
                alerte.send(channel(did), h, post)
                out.append(h["id"])
            except Exception:
                pass
        return out


STORE = Store()
