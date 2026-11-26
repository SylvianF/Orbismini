"""Proposition de rachat envoyée au client depuis l’application iPhone (« Envoyer au client »).

Le PDF est la même « Proposition de rachat » qu’Orbis : proposition_pdf.py en est une copie tel
quel (prévenu par la session Orbis à chaque changement). Les mentions des agences (raison
sociale, adresse, téléphone, e-mail) sont dans agences-proposition.json, fournies par Orbis.
Rien n’est gardé ici : le PDF est fabriqué, rendu au téléphone, puis oublié.
"""

import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
AGENCIES = ROOT / "agences-proposition.json"
LIMIT = 200  # caractères au plus pour chaque champ saisi sur le téléphone


def agencies():
    """{ville: {company, address, phone, email}} ; {} si les mentions manquent encore."""
    try:
        data = json.loads(AGENCIES.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    keys = ("company", "address", "phone", "email")
    return {city: {k: str(v.get(k) or "") for k in keys} for city, v in data.items()
            if isinstance(v, dict) and all(str(v.get(k) or "").strip() for k in ("company", "address"))}


def paris_now():
    """Heure de Paris (Render tourne en heure universelle)."""
    try:
        from zoneinfo import ZoneInfo

        return datetime.now(ZoneInfo("Europe/Paris")).replace(tzinfo=None)
    except Exception:
        return datetime.now()


def make(body, now=None):
    """Octets du PDF ; ValueError si la demande est incomplète, LookupError si l’agence manque."""
    import proposition_pdf

    if not isinstance(body, dict):
        raise ValueError("Demande illisible.")
    rows = body.get("rows")
    if not isinstance(rows, list) or not rows or len(rows) > 100:
        raise ValueError("Complète les lignes de l’estimation.")
    known = agencies()
    city = str(body.get("agence") or "").strip()
    if city not in known:
        raise LookupError("Mentions de l’agence « " + city[:30] + " » pas encore fournies par Orbis.")
    given = body.get("client") if isinstance(body.get("client"), dict) else {}
    client = {k: str(given.get(k) or "").strip()[:LIMIT] for k in ("name", "phone", "email")}
    contact = str(body.get("contact") or "").strip()[:LIMIT]
    return proposition_pdf.make(rows, client, known[city], contact, now=now or paris_now(), internal=False)
