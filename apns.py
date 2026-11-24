"""Notifications de l’application iPhone d’Orbismini (APNs d’Apple), à côté de ntfy.

Éteint tant que la variable ORBISMINI_APNS ne vaut pas « 1 » sur Render : rien n’est alors
enregistré ni envoyé, et ntfy (le Samsung, les anciens iPhone) marche exactement comme avant.
Allumé, chaque alerte qui part vers ntfy part aussi vers les iPhone qui ont l’application.

Réglages de Render (jamais dans le dépôt) :
  ORBISMINI_APNS = 1          interrupteur
  APNS_KEY       = contenu du fichier AuthKey_XXXXXXXXXX.p8 (clé d’Apple pour les notifications)
  APNS_KEY_ID    = les 10 caractères de cette clé
  APNS_TEAM_ID   = identifiant d’équipe Apple (10 caractères)
  APNS_TOPIC     = identifiant de l’application (fr.cndo.orbismini)

Dépendances (requirements.txt), chargées seulement quand l’interrupteur est allumé :
httpx[http2] (Apple n’accepte que HTTP/2) et cryptography (signature ES256 du jeton)."""

import base64
import json
import os
import re
import threading
import time

HOSTS = {"production": "https://api.push.apple.com", "sandbox": "https://api.sandbox.push.apple.com"}
TOKEN = re.compile(r"[0-9a-f]{64,200}")
JWT_MINUTES = 40          # Apple refuse un jeton de plus d’une heure et un nouveau toutes les 20 min
REJECTED = {"BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"}
_lock = threading.Lock()
_jwt = [0.0, ""]
_client = [None]


def enabled():
    """Vrai seulement si l’interrupteur est allumé et la clé d’Apple complète."""
    if os.environ.get("ORBISMINI_APNS", "").strip() != "1":
        return False
    return all(os.environ.get(k, "").strip() for k in ("APNS_KEY", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC"))


def clean_token(token, env):
    """(jeton, environnement) vérifiés ; ValueError sinon."""
    token = str(token or "").strip().lower()
    env = str(env or "production").strip().lower()
    if not TOKEN.fullmatch(token):
        raise ValueError("Jeton de notification invalide")
    if env not in HOSTS:
        raise ValueError("Environnement de notification inconnu")
    return token, env


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _pem():
    """Clé .p8 telle que collée dans Render : texte PEM, avec \\n écrits, ou en base64."""
    raw = os.environ.get("APNS_KEY", "").strip().replace("\\n", "\n")
    if "BEGIN" not in raw:
        raw = base64.b64decode(raw).decode()
    return raw.encode()


def jwt(now=None):
    """Jeton signé ES256 pour Apple, gardé 40 minutes."""
    now = time.time() if now is None else now
    with _lock:
        if _jwt[1] and now - _jwt[0] < JWT_MINUTES * 60:
            return _jwt[1]
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

        head = _b64(json.dumps({"alg": "ES256", "kid": os.environ["APNS_KEY_ID"].strip()}).encode())
        body = _b64(json.dumps({"iss": os.environ["APNS_TEAM_ID"].strip(), "iat": int(now)}).encode())
        key = serialization.load_pem_private_key(_pem(), password=None)
        r, s = decode_dss_signature(key.sign((head + "." + body).encode(), ec.ECDSA(hashes.SHA256())))
        token = head + "." + body + "." + _b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
        _jwt[:] = [now, token]
        return token


def _post(url, headers, payload):
    """Envoi HTTP/2 vers Apple : (statut, raison)."""
    import httpx

    with _lock:
        if _client[0] is None:
            _client[0] = httpx.Client(http2=True, timeout=10)
        client = _client[0]
    r = client.post(url, headers=headers, content=payload)
    try:
        reason = r.json().get("reason", "")
    except ValueError:
        reason = ""
    return r.status_code, reason


def send(tokens, title, body, post=None, screen="alerte"):
    """Une notification vers chaque (jeton, environnement). Renvoie les jetons qu’Apple refuse
    pour de bon (application effacée…), à oublier. Ne lève jamais : ntfy ne doit rien sentir."""
    if not enabled() or not tokens:
        return []
    post = post or _post
    payload = json.dumps(
        {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}, "ecran": screen},
        ensure_ascii=False,
    ).encode("utf-8")
    gone = []
    for token, env in tokens:
        try:
            headers = {
                "authorization": "bearer " + jwt(),
                "apns-topic": os.environ["APNS_TOPIC"].strip(),
                "apns-push-type": "alert",
                "apns-priority": "10",
            }
            status, reason = post(HOSTS.get(env, HOSTS["production"]) + "/3/device/" + token, headers, payload)
            if status == 410 or (status == 400 and reason in REJECTED):
                gone.append(token)
            elif status == 403 and reason == "ExpiredProviderToken":
                _jwt[:] = [0.0, ""]
        except Exception:
            pass
    return gone


def send_hit(tokens, h, post=None):
    """Alerte de cours (même texte que ntfy, alerte.message)."""
    import alerte

    title, body = alerte.message(h)
    return send(tokens, title, body, post)
