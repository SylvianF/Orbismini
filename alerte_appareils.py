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
tirée du mot de passe d’Orbismini (réglages de Render), donc introuvable depuis le dépôt.

Événements d’Orbis (demandes de virement, transferts entre agences ; par ville : achats, ventes,
achats à risque, vente directe) : Orbis choisit quels téléphones les reçoivent (cases cochées dans
Orbis, « events » ici : « virement », « transfert », « achat:Nancy », « risque:Calais », « vd:Troyes »…) et les annonce au serveur, qui les envoie à
l’application iPhone de ces téléphones. Le nom donné au téléphone dans l’application
est rangé chiffré (clé tirée du mot de passe d’Orbismini) : le dépôt ne montre aucun nom."""

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
# Événements d’Orbis qu’un téléphone peut recevoir. « risque » : achat à marge théorique négative ou
# à % GtaX inhabituel (seuils réglés dans Orbis) ; « vd » : vente directe en cours à envoyer ou prête
# à vendre.
EVENTS = ("virement", "transfert", "achat", "vente", "risque", "vd")
CITY_EVENTS = ("achat", "vente", "risque", "vd")   # choisis ville par ville : « achat:Nancy »
CITY = re.compile(r"[^\W\d_][^\W\d_' -]{0,28}[^\W\d_]|[^\W\d_]{1,2}")
SHORT = re.compile(r"[0-9a-f]{16}")  # identifiant d’un téléphone donné à Orbis (début de l’empreinte)
NAME_MAX = 40


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


def _name_key():
    password = os.environ.get("GOLDAPP_PASSWORD", "")
    return hashlib.sha256(("orbismini-nom:" + password).encode()).digest()


KEPT_SPACES = "\u00a0\u202f"   # espaces insécables (milliers : « 1 240 € ») : gardées


def _short_text(value, limit):
    text = "".join(c if c.isprintable() or c in KEPT_SPACES else " " for c in str(value or ""))
    return re.sub(r" +", " ", text).strip()[:limit]


def clean_name(name):
    """Nom donné au téléphone dans l’application (« Sylvian », « Magasin »…), 40 caractères au plus."""
    return _short_text(name, NAME_MAX)


def _stream(key, nonce, size):
    out, n = b"", 0
    while len(out) < size:
        out += hmac.new(key, nonce + n.to_bytes(4, "big"), hashlib.sha256).digest()
        n += 1
    return out[:size]


def seal_name(name):
    """Nom chiffré pour le dépôt (lisible seulement avec le mot de passe d’Orbismini)."""
    key, nonce, raw = _name_key(), os.urandom(12), name.encode("utf-8")
    sealed = bytes(a ^ b for a, b in zip(raw, _stream(key, nonce, len(raw))))
    tag = hmac.new(key, b"nom" + nonce + sealed, hashlib.sha256).digest()[:16]
    return base64.urlsafe_b64encode(nonce + sealed + tag).decode()


def open_name(blob):
    """Nom en clair ; « » s’il est absent ou illisible (mot de passe changé…)."""
    try:
        raw = base64.urlsafe_b64decode(str(blob or "").encode())
        if len(raw) < 28:
            return ""
        nonce, sealed, tag = raw[:12], raw[12:-16], raw[-16:]
        key = _name_key()
        if not hmac.compare_digest(tag, hmac.new(key, b"nom" + nonce + sealed, hashlib.sha256).digest()[:16]):
            return ""
        return bytes(a ^ b for a, b in zip(sealed, _stream(key, nonce, len(sealed)))).decode("utf-8")
    except (ValueError, UnicodeDecodeError):
        return ""


def _city(value):
    """Ville d’un achat ou d’une vente (« Nancy », « Saint-Dizier »…) ; ValueError sinon."""
    city = _short_text(value, 30)
    if not CITY.fullmatch(city):
        raise ValueError("Ville invalide : " + city[:30])
    return city


def clean_event(value):
    """« virement », « transfert », « achat:Nancy », « vente:Calais » ; ValueError sinon."""
    text = str(value or "").strip()
    kind, _, city = text.partition(":")
    if kind in CITY_EVENTS and city:
        return kind + ":" + _city(city)
    if kind in EVENTS and kind not in CITY_EVENTS and not city:
        return kind
    raise ValueError("Événement inconnu : " + text[:40] + " (virement, transfert, achat:Ville, vente:Ville).")


def _event_order(e):
    kind, _, city = e.partition(":")
    return EVENTS.index(kind), city.lower()


def _today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


class Store:
    def __init__(self, token=None):
        self.token = os.environ.get("ORBISCAN_GITHUB_TOKEN", "").strip() if token is None else token
        self.lock = threading.RLock()
        self.data = None     # {"devices": {id: {state, seen}}, "orbis": [id, …]}
        self.sha = None
        self.sent = set()
        self.checked = float("-inf")   # le premier contrôle passe, même juste après un démarrage

    # ---------------------------------------------------------------- GitHub
    def _load(self):
        if self.data is not None:
            return
        if not self.token:
            raise PermissionError("Alertes par téléphone indisponibles (ORBISCAN_GITHUB_TOKEN absent)")
        status, data, sha = orbiscan_pc.read_file(self.token, BRANCH, FILE)
        if data is None:
            raise PermissionError("Alertes illisibles pour l’instant, réessaie dans une minute (GitHub %s)" % status)
        self.sha = sha
        self.data = dict(devices=dict(data.get("devices") or {}), orbis=list(data.get("orbis") or []))
        # Alertes déjà connues au démarrage : pas renvoyées.
        self.sent.update(h["id"] for d in self.data["devices"].values() for h in d["state"].get("hits") or [])

    def _save(self, data, message):
        text = json.dumps(data, indent=1, sort_keys=True, ensure_ascii=False)
        status, sha = orbiscan_pc.write_file(self.token, BRANCH, FILE, self.sha, text, message)
        if sha is None:
            self.data = None             # relire au prochain passage
            raise PermissionError("Alerte non enregistrée, réessaie dans une minute (GitHub %s)" % status)
        self.sha, self.data = sha, data

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
    def check(self, price_loader, post=None, apns_post=None):
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
            self.push(lambda: self.apns_tokens(did), h, apns_post)
        return out

    # ---------------------------------------------------------------- application iPhone (apns.py)
    MAX_APNS = 3

    def set_apns(self, did, token, env, name=None):
        """Jeton de notification de l’application iPhone pour ce téléphone (vide : retiré), et le
        nom donné au téléphone dans l’application (None : inchangé, « » : retiré).
        Un jeton seul ne sert à rien sans la clé d’Apple, rangée dans les réglages de Render."""
        import apns

        entry = None if not token else dict(zip(("token", "env"), apns.clean_token(token, env)))
        name = None if name is None else clean_name(name)
        with self.lock:
            self._load()
            data = self._copy()
            for other in data["devices"].values():
                if entry and other.get("apns"):
                    other["apns"] = [t for t in other["apns"] if t["token"] != entry["token"]]
            d = data["devices"].get(did)
            if not d:
                if not entry:
                    return
                self._prune(data)
                if len(data["devices"]) >= MAX_DEVICES:
                    raise PermissionError("Trop de téléphones avec une alerte")
                d = data["devices"][did] = dict(state={"hits": []})
            kept = [t for t in d.get("apns") or [] if not entry or t["token"] != entry["token"]]
            d["apns"] = ((kept + [entry]) if entry else [])[-self.MAX_APNS:]
            if not d["apns"]:
                d.pop("apns")
            if name is not None and name != open_name(d.get("nom")):
                if name:
                    d["nom"] = seal_name(name)
                else:
                    d.pop("nom", None)
            d["seen"] = _today()
            if data != self.data:
                self._save(data, "Notifications de l’application iPhone d’un téléphone")

    def apns_tokens(self, did):
        with self.lock:
            self._load()
            d = self.data["devices"].get(did) or {}
            return [(t["token"], t["env"]) for t in d.get("apns") or []]

    def orbis_apns(self):
        """Jetons des téléphones reliés à l’alerte commune avec Orbis."""
        with self.lock:
            self._load()
            return [x for did in self.data["orbis"] for x in self.apns_tokens(did)]

    def forget_apns(self, tokens):
        if not tokens:
            return
        with self.lock:
            self._load()
            data = self._copy()
            for d in data["devices"].values():
                if d.get("apns"):
                    d["apns"] = [t for t in d["apns"] if t["token"] not in tokens]
                    if not d["apns"]:
                        d.pop("apns")
            if data != self.data:
                self._save(data, "Notifications de l’application iPhone : jeton périmé retiré")

    # ---------------------------------------------------------------- événements d’Orbis
    def phones(self):
        """Téléphones qui ont l’application iPhone (écran d’Orbis qui choisit qui reçoit quoi)."""
        with self.lock:
            self._load()
            out = [dict(id=did[:16], nom=open_name(d.get("nom")), vu=d.get("seen", ""),
                        evenements=list(d.get("events") or []))
                   for did, d in self.data["devices"].items() if d.get("apns")]
        return sorted(out, key=lambda x: (x["nom"] == "", x["nom"].lower(), x["id"]))

    def set_events(self, short, events):
        """Événements d’Orbis que reçoit ce téléphone (cases cochées dans Orbis)."""
        short = str(short or "").strip().lower()
        if not SHORT.fullmatch(short):
            raise ValueError("Téléphone inconnu.")
        if not isinstance(events, list):
            raise ValueError("Liste d’événements attendue.")
        unique = {}
        for e in events:
            e = clean_event(e)
            unique.setdefault(e.lower(), e)          # même ville écrite autrement : la première gardée
        chosen = sorted(unique.values(), key=_event_order)
        with self.lock:
            self._load()
            found = [did for did in self.data["devices"] if did.startswith(short)]
            if len(found) != 1:
                raise ValueError("Téléphone inconnu.")
            data = self._copy()
            d = data["devices"][found[0]]
            if chosen:
                d["events"] = chosen
            else:
                d.pop("events", None)
            if data != self.data:
                self._save(data, "Événements d’Orbis choisis pour un téléphone")
        return self.phones()

    def event(self, kind, eid, title, body, post=None, city=None):
        """Événement annoncé par Orbis → application iPhone des téléphones qui l’ont choisi.
        Achat et vente : ville obligatoire, seuls les téléphones cochés pour cette ville reçoivent,
        et la notification ouvre l’onglet Chiffres. Renvoie le nombre de téléphones atteints ; une
        même annonce (kind, eid) ne part qu’une fois."""
        import apns

        if kind not in EVENTS:
            raise ValueError("Événement inconnu : " + ", ".join(EVENTS) + " seulement.")
        wanted = (kind + ":" + _city(city)).lower() if kind in CITY_EVENTS else kind
        eid, title, body = _short_text(eid, 80), _short_text(title, 100), _short_text(body, 300)
        if not eid or not title:
            raise ValueError("Identifiant et titre de l’événement nécessaires.")
        mark = "orbis:" + kind + ":" + eid
        with self.lock:
            if mark in self.sent:
                return 0
            self._load()
            chosen = [did for did, d in self.data["devices"].items()
                      if wanted in [e.lower() for e in d.get("events") or []]]
            tokens = [x for did in chosen for x in self.apns_tokens(did)]
            if not apns.enabled() or not tokens:
                return 0
            self.sent.add(mark)
        gone = apns.send(tokens, title, body, post, screen="chiffres" if kind in CITY_EVENTS else "orbis")
        self.forget_apns(gone)
        return len([did for did in chosen if self.apns_tokens(did)])

    def push(self, tokens, h, post=None):
        """Alerte vers l’application iPhone, seulement si apns.py est allumé ; jamais d’erreur.
        tokens : fonction qui donne les jetons (lue seulement quand c’est allumé)."""
        import apns

        try:
            if apns.enabled():
                self.forget_apns(apns.send_hit(tokens(), h, post))
        except Exception:
            pass


STORE = Store()
