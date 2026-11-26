"""Serveur de Mon Cours de l’Or : application et cotations, mêmes sources que l’ancienne GoldApp.

Sources :
  - or pur (valeur intrinsèque) : Kitco Bid en €/kg ; BullionVault en secours ;
  - pièces et lingots boursables : cotations CPoR (Loomis), comme l’ancienne GoldApp ;
  - argent : cotations Gold.fr ; argent C3E achat : Cookson-Clal ;
  - graphique : historique BullionVault.
Chaque source est mise en cache quelques secondes pour ne pas solliciter les sites
à chaque actualisation.
"""

from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path, PurePosixPath
from html.parser import HTMLParser
from urllib.request import Request, urlopen
from urllib.parse import urlparse, parse_qs, unquote
from datetime import datetime, timezone
from http.cookies import SimpleCookie
import hashlib, hmac, json, os, re, unicodedata, time

ROOT = Path(__file__).resolve().parent
BASE = "https://www.gold.fr"
# Seuls les fichiers de l’application sont publiés (pas le code serveur ni les notes).
PUBLIC_SUFFIXES = {".html", ".js", ".css", ".png", ".svg", ".webp", ".webmanifest", ".ico", ".jpg"}
PRIVATE = {"server.py"}

# Mot de passe à l’ouverture : variable d’environnement GOLDAPP_PASSWORD (réglée sur Render).
# Sans elle, l’application reste ouverte comme avant.
PASSWORD = os.environ.get("GOLDAPP_PASSWORD", "")
SESSION_DAYS = 180
# Clé du widget iPhone (Scriptable) : lecture seule des cours, sans le mot de passe.
# Variable GOLDAPP_WIDGET_KEY sur Render ; sans elle, /api/widget est fermé.
WIDGET_KEY = os.environ.get("GOLDAPP_WIDGET_KEY", "")
# Alerte de cours commune avec Orbis : clé d’échange tirée du mot de passe (alerte.py).
ALERT_KEY = __import__("alerte").key_from_password(PASSWORD) if PASSWORD else ""
# Fichiers lisibles sans mot de passe, pour l’icône de l’écran d’accueil.
OPEN_FILES = {"/manifest.webmanifest", "/icon.svg", "/icon.png", "/favicon.ico"}
LOGIN_PAGE = """<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#121d25"><meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Orbismini">
<link rel="manifest" href="manifest.webmanifest"><link rel="apple-touch-icon" href="icon.png">
<title>Orbismini</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
background:radial-gradient(60% 40% at 50% 35%,rgba(233,191,117,.12),transparent 70%),#121d25;
color:#edf2f5;font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif}
form{width:min(340px,calc(100% - 32px));display:grid;gap:14px;text-align:center}
img{width:84px;height:84px;margin:0 auto 4px;border-radius:18px;box-shadow:0 10px 40px #0008}
h1{margin:0;font-size:26px;font-weight:600}p{margin:0;color:#b5c7d3;font-size:14px}
input{width:100%;min-height:50px;padding:12px 14px;border:1px solid #344853;border-radius:12px;
background:#101c24;color:#edf2f5;font:inherit;font-size:17px;text-align:center}
input:focus{outline:2px solid #e9bf75;outline-offset:2px}
button{min-height:50px;border:0;border-radius:12px;background:#e9bf75;color:#18242b;font:inherit;
font-weight:650;cursor:pointer}
.error{color:#ffb3ad}
</style></head><body>
<form method="post" action="login">
<img src="icon.svg" alt="">
<h1><span style="color:#e9bf75">Orbis</span>mini</h1>
<p>Saisis le mot de passe pour ouvrir l’application.</p>
<input type="text" name="username" value="GoldApp" autocomplete="username" hidden>
<input type="password" name="password" autocomplete="current-password" placeholder="Mot de passe" required autofocus>
__ERROR__
<button type="submit">Ouvrir</button>
</form></body></html>"""


def session_token():
    """Jeton de session : dérivé du mot de passe, il change si le mot de passe change."""
    return hmac.new(PASSWORD.encode(), b"goldapp-session-v1", hashlib.sha256).hexdigest()


class HTMLText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.rows = []
        self.row = None
        self.cell = None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        if tag in ("td", "th") and self.row is not None:
            self.cell = []

    def handle_data(self, data):
        self.parts.append(data)
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None and self.row is not None:
            self.row.append(" ".join(" ".join(self.cell).split()))
            self.cell = None
        if tag == "tr" and self.row is not None:
            if self.row:
                self.rows.append(self.row)
            self.row = None


def fetch(path):
    req = Request(
        BASE + path,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; PersonalGoldDashboard/1.0)",
            "Accept-Language": "fr-FR,fr;q=0.9",
        },
    )
    with urlopen(req, timeout=16) as r:
        return r.read().decode("utf-8", errors="replace")


def normalize(s):
    return "".join(
        c
        for c in unicodedata.normalize("NFKD", s.lower())
        if not unicodedata.combining(c)
    ).replace("’", "'")


def euro(s):
    m = re.search(r"(?<!\d)(\d[\d\s\u00a0.,]*?)\s*€", s)
    if not m:
        return None
    t = m.group(1).replace("\u00a0", "").replace(" ", "")
    if "," in t and "." in t:
        t = t.replace(".", "").replace(",", ".")
    elif "," in t:
        t = t.replace(",", ".")
    elif "." in t and len(t.rsplit(".", 1)[-1]) == 3:
        t = t.replace(".", "")
    try:
        return float(t)
    except ValueError:
        return None


def extract_c3e(html):
    parser = HTMLText()
    parser.feed(html)
    text = " ".join(" ".join(parser.parts).split())
    # Lecture des seules cellules de la ligne C3E, dans le tableau achat/vente.
    rows = [
        cells
        for cells in parser.rows
        if any(normalize(c) == "argent c3e" for c in cells)
    ]
    if len(rows) != 1:
        raise ValueError("Ligne Argent C3E absente ou ambiguë")
    row = rows[0]
    idx = next(i for i, c in enumerate(row) if normalize(c) == "argent c3e")
    amounts = [c for c in row[idx + 1 :] if c.strip()]
    if len(amounts) != 2 or not all(
        re.fullmatch(r"[\d\s.,]+\s*€/\s*kg", c) for c in amounts
    ):
        raise ValueError("Colonnes C3E achat/vente non reconnues")
    # Le prix achat doit rester associé à l'en-tête achat précédant vente.
    normalized = normalize(text)
    block = normalized.split("metaux industriels", 1)[-1].split("argent c3e", 1)[0]
    if not re.search(r"achat\s+vente", block):
        raise ValueError("En-tête achat/vente C3E non reconnu")
    dates = re.findall(r"(?:le|du)\s+(\d{2}/\d{2}/\d{4})", block)
    if not dates:
        raise ValueError("Date du cours C3E non trouvée")
    source_date = datetime.strptime(dates[-1], "%d/%m/%Y").date().isoformat()
    value = euro(amounts[0])
    if value is None or value <= 0:
        raise ValueError("Prix achat C3E invalide")
    return {
        "price": value,
        "sourceDate": source_date,
        "unit": "EUR/kg",
        "side": "achat",
        "source": "https://www.cookson-clal.com/cours/",
    }


def c3e_live():
    req = Request(
        "https://www.cookson-clal.com/cours/",
        headers={"User-Agent": "Mozilla/5.0", "Accept-Language": "fr-FR"},
    )
    with urlopen(req, timeout=16) as response:
        html = response.read().decode("utf-8", errors="replace")
    return {**extract_c3e(html), "updatedAt": datetime.now(timezone.utc).isoformat()}


SILVER_LABELS = [
    "Lingot Argent 1Kg",
    "Maple Leaf 1 Oz",
    "Vienna Philharmonic 1 Oz",
    "Kangourou 1 Oz",
    "Britannia 1 Oz",
    "American Eagle 1 Oz",
    "Krugerrand Argent 1 Oz",
    "China Panda 30g 2025-26",
    "Kookaburra 1 Oz",
    "Koala 1 Oz",
    "Kookaburra 1Kg (2008-2018)",
    "Koala Argent 1Kg 2025-2026",
    "20 Francs Turin en Argent",
    "50 Francs Hercule",
    "5 Francs Semeuse en Argent",
    "10 Francs Hercule",
    "10 Francs Turin",
    "5 Francs Hercule en Argent (Ecu)",
    "100 Francs en Argent",
]


def extract_silver(html):
    parser = HTMLText()
    parser.feed(html)
    products = []
    # Lecture exclusive de la cellule qui suit le nom du produit.
    # Aucun recours au tableau international ni aux variations/primes.
    for label in SILVER_LABELS:
        matches = []
        for cells in parser.rows:
            for i, cell in enumerate(cells[:-1]):
                if normalize(cell) == normalize(label):
                    matches.append(cells[i + 1])
        price = None
        status = "unavailable"
        if len(matches) == 1:
            if "suspendue" in normalize(matches[0]):
                status = "suspended"
            else:
                price = euro(matches[0])
                if price is not None and price > 0:
                    status = "available"
                else:
                    price = None
        products.append({"name": label, "price": price, "status": status})
    if not any(p["status"] in ("available", "suspended") for p in products):
        raise ValueError("Tableau des cours argent non reconnu")
    return products


def silver_live():
    return {
        "products": extract_silver(fetch("/cours-argent-prix-de-l-argent/")),
        "updatedAt": datetime.now(timezone.utc).isoformat(),
        "source": BASE + "/cours-argent-prix-de-l-argent/",
    }


_cache = {}


def cached(key, seconds, loader):
    item = _cache.get(key)
    if item and time.time() - item[0] < seconds:
        return item[1]
    value = loader()
    _cache[key] = (time.time(), value)
    return value


def spot_live():
    """Or pur en €/kg : Kitco Bid, sinon BullionVault (signalé comme secours)."""

    def load():
        errors = []
        try:
            from kitco import fetch_quote

            quote = fetch_quote()
            return dict(
                price=quote["price"],
                updatedAt=quote["quotedAt"],
                retrievedAt=quote["retrievedAt"],
                source="Kitco",
                basis="Bid",
                unit="EUR/kg",
                currency="EUR",
                marketClosed=quote.get("marketClosed", False),
            )
        except Exception as error:
            errors.append("Kitco : " + str(error)[:100])
        try:
            from bullionvault import fetch_quote as bullionvault_quote

            quote = bullionvault_quote()
            return dict(
                price=quote["price"],
                updatedAt=quote["quotedAt"],
                retrievedAt=quote["retrievedAt"],
                marketClosed=quote.get("marketClosed", False),
                source="BullionVault",
                basis="secours",
                unit="EUR/kg",
                currency="EUR",
                warning=errors[0],
            )
        except Exception as error:
            errors.append("BullionVault : " + str(error)[:100])
        raise ValueError("Or pur indisponible (" + " ; ".join(errors) + ")")

    return cached("spot", 10, load)


def thin(points, limit=120):
    """Allège une courbe pour le widget : au plus `limit` points, le dernier conservé."""
    if len(points) <= limit:
        return points
    step = len(points) / limit
    kept = [points[int(i * step)] for i in range(limit - 1)]
    return kept + [points[-1]]


def widget_live(period="1"):
    """Cours et courbes de l’or et de l’argent, en un seul appel, pour le widget."""
    if period not in ("1", "7", "30", "365"):
        raise ValueError("Période non disponible")
    result = dict(period=period, updatedAt=datetime.now(timezone.utc).isoformat())
    for metal in ("gold", "silver"):
        try:
            history = history_live(period, metal)
            points = [[p["date"], round(p["price"], 2)] for p in history["points"]]
            result[metal] = dict(points=thin(points), price=points[-1][1], source="BullionVault")
        except Exception as error:
            result[metal] = dict(error=str(error)[:160])
    try:
        spot = spot_live()
        result["gold"].update(
            price=spot["price"],
            source=spot["source"],
            quotedAt=spot.get("updatedAt"),
            marketClosed=bool(spot.get("marketClosed")),
        )
    except Exception:
        pass
    return result


def history_live(period="1", metal="gold"):
    from bullionvault_history import fetch_history

    return cached(
        "history-bullionvault-" + metal + "-" + period, 60, lambda: fetch_history(period, metal)
    )


def weather_live():
    """Météo de l’or (gardée 30 min dans meteo_or), page réservée après le mot de passe."""
    import meteo_or

    def refs():
        prices = live_prices()["prices"]
        return {"instant": prices.get("instant"), "quotes": prices}

    meteo_or.refs_loader = refs
    return meteo_or.weather()


def live_prices():
    """Valeur intrinsèque (Kitco / BullionVault) et cotations CPoR (Loomis)."""

    def load():
        prices, warnings, source = {}, [], None
        try:
            spot = spot_live()
            prices["instant"] = spot["price"]
            source = spot["source"]
            if spot.get("warning"):
                warnings.append("Kitco indisponible, BullionVault utilisé")
        except Exception as error:
            warnings.append(str(error)[:160])
        quoted_at = None
        try:
            import cpor

            quotes = cpor.live()
            prices.update(quotes["prices"])
            quoted_at = quotes["quotedAt"]
            missing = [p["name"] for p in quotes["products"] if not p["price"]]
            if missing:
                warnings.append("Cotation suspendue : " + ", ".join(missing))
        except Exception as error:
            warnings.append("Cotations CPoR indisponibles : " + str(error)[:100])
        if not prices:
            raise ValueError("Aucun cours extrait. " + " ; ".join(warnings))
        return {
            "prices": prices,
            "instantSource": source,
            "cporQuotedAt": quoted_at,
            "updatedAt": datetime.now(timezone.utc).isoformat(),
            "warnings": warnings,
            "origin": "Kitco / CPoR (Loomis)",
        }

    return cached("prices", 30, load)


ROUTES = {
    "/api/prices": lambda query: live_prices(),
    "/api/c3e": lambda query: cached("c3e", 60, c3e_live),
    "/api/silver": lambda query: cached("silver", 60, silver_live),
    "/api/spot": lambda query: spot_live(),
    "/api/weather": lambda query: weather_live(),
    "/api/widget": lambda query: widget_live(query.get("period", ["1"])[0]),
    "/api/spot-history": lambda query: history_live(
        query.get("period", ["1"])[0], query.get("metal", ["gold"])[0]
    ),
}


def alert_price():
    """Dernier cours de l’or (BullionVault, €/kg) : (prix, moment, cours 24 h plus tôt)."""
    points = history_live("1", "gold")["points"]
    return points[-1]["price"], points[-1]["date"], points[0]["price"]


def alert_view(with_price):
    """État de l’alerte ; pour l’iPhone (session) : cours actuel et canal ntfy."""
    import alerte

    out = alerte.state()
    if with_price:
        out["channel"] = alerte.channel(ALERT_KEY)
        try:
            out["price"] = alert_price()[0]
        except Exception:
            pass
    return out


def apns_orbis(h):
    """Alerte commune avec Orbis : aussi vers l’application iPhone des téléphones reliés (apns.py,
    éteint par défaut ; ntfy n’en dépend pas)."""
    import alerte_appareils as AA

    AA.STORE.push(AA.STORE.orbis_apns, h)


__import__("alerte").LISTENERS.append(apns_orbis)


def public(route):
    """Vrai pour un fichier de l’application ; faux pour le code serveur et les notes."""
    path = PurePosixPath(unquote(route))
    if route in ("/", ""):
        return True
    if any(part.startswith(".") for part in path.parts) or path.name in PRIVATE:
        return False
    return path.suffix.lower() in PUBLIC_SUFFIXES


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self):
        # Revalider les fichiers de l’application pour les sessions Safari/PWA longues.
        if not self.path.split("?")[0].startswith("/api/"):
            self.send_header("Cache-Control", "no-cache, must-revalidate")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(404)
        return None

    def authorized(self):
        if not PASSWORD:
            return True
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get("Cookie", ""))
        except Exception:
            return False
        given = cookie.get("goldapp_session")
        return bool(given) and hmac.compare_digest(given.value, session_token())

    def send_login(self, status=401, error=""):
        body = LOGIN_PAGE.replace(
            "__ERROR__", '<p class="error" role="alert">' + error + "</p>" if error else ""
        ).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def set_session(self, value, max_age):
        secure = "; Secure" if self.headers.get("X-Forwarded-Proto") == "https" else ""
        self.send_header(
            "Set-Cookie",
            "goldapp_session=" + value + "; Path=/; Max-Age=" + str(max_age)
            + "; HttpOnly; SameSite=Lax" + secure,
        )

    def widget_allowed(self):
        given = self.headers.get("X-Widget-Key", "")
        return bool(WIDGET_KEY) and hmac.compare_digest(given.encode(), WIDGET_KEY.encode())

    def alert_allowed(self):
        given = self.headers.get("X-Alert-Key", "")
        return bool(ALERT_KEY) and hmac.compare_digest(given.encode(), ALERT_KEY.encode())

    def orbis_events(self, method):
        """Événements d’Orbis (demandes de virement, transferts, achats et ventes) : téléphones qui ont l’application,
        cases cochées dans Orbis, annonces. Clé d’Orbis seule (X-Alert-Key) ; vrai si traité ici."""
        path = urlparse(self.path).path
        if path not in ("/api/orbis/telephones", "/api/orbis/evenement"):
            return False
        if not self.alert_allowed():
            time.sleep(1)
            self.send_json({"error": "Clé d’Orbis absente ou incorrecte."}, 403)
            return True
        import alerte_appareils as AA
        import apns

        try:
            body = {}
            if method == "POST":
                length = min(int(self.headers.get("Content-Length") or 0), 8192)
                body = json.loads(self.rfile.read(length) or b"{}")
                if not isinstance(body, dict):
                    raise ValueError("Objet JSON attendu.")
            if path == "/api/orbis/telephones":
                if method == "POST":
                    phones = AA.STORE.set_events(body.get("id"), body.get("evenements"))
                else:
                    phones = AA.STORE.phones()
                self.send_json({"telephones": phones, "notifications": apns.enabled(),
                                "evenements": list(AA.EVENTS)})
            elif method == "POST":
                n = AA.STORE.event(body.get("type"), body.get("id"), body.get("titre"), body.get("texte"),
                                   city=body.get("ville"))
                self.send_json({"envoye": n, "notifications": apns.enabled()})
            else:
                self.send_json({"error": "POST attendu."}, 405)
        except (ValueError, TypeError) as error:
            self.send_json({"error": str(error)[:200]}, 400)
        except PermissionError as error:
            self.send_json({"error": str(error)[:200]}, 503)
        return True

    def phone_alert(self, body=None):
        """Alerte du téléphone (session + identifiant X-Appareil) : la sienne, ou celle d’Orbis
        s’il y est relié. None : demande d’Orbis ou d’une ancienne page (alerte commune)."""
        import alerte
        import alerte_appareils as AA

        did = AA.device_id(self.headers.get("X-Appareil"))
        if not did or not self.authorized():
            return None
        if AA.STORE.linked(did):
            if body is not None:
                alerte.update(body, ALERT_KEY)
            return dict(alert_view(True), mode="orbis")
        out = AA.STORE.update(did, body) if body is not None else AA.STORE.view(did)
        try:
            out["price"] = alert_price()[0]
        except Exception:
            pass
        return dict(out, mode="appareil")

    def send_json(self, data, status=200):
        payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def guard(self, path):
        """Vrai si la requête peut continuer ; sinon la page de connexion est envoyée."""
        if path == "/api/alert/check":
            return True  # contrôle seul, appelé par GitHub Actions : rien n’en sort
        if path == "/api/alert" and self.alert_allowed():
            return True  # Orbis : clé tirée du mot de passe
        if path == "/api/widget":
            # Le widget n’a que sa clé : ni la session, ni le mot de passe ne l’ouvrent.
            if self.widget_allowed():
                return True
            time.sleep(1)
            payload = b'{"error": "Cle du widget absente ou incorrecte"}'
            self.send_response(403)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return False
        if self.authorized() or path in OPEN_FILES:
            return True
        if path.startswith("/api/"):
            payload = b'{"error": "Mot de passe requis"}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_login()
        return False

    def log_message(self, format, *args):
        # Orbiscan : aucune trace des adresses (jetons de jumelage) dans les journaux de Render.
        if "orbiscan" in (getattr(self, "path", "") or ""):
            return
        super().log_message(format, *args)

    def client_ip(self):
        """Adresse du téléphone ou du PC sur internet. Jamais X-Forwarded-For : son début est écrit par
        l'appelant et sa fin par Render (adresses internes, les mêmes pour tous). Vérifié sur Render le
        15/11/2026 : True-Client-IP et CF-Connecting-IP sont posés par Cloudflare, une valeur envoyée par
        l'appelant est remplacée (True-Client-IP) ou la demande refusée (CF-Connecting-IP)."""
        for header in ("True-Client-IP", "CF-Connecting-IP"):
            value = (self.headers.get(header) or "").strip()
            if value:
                return value
        return self.client_address[0]

    def read_limited(self, limit):
        length = int(self.headers.get("Content-Length") or 0)
        if length < 0 or length > limit:
            raise ValueError("trop lourd")
        return self.rfile.read(length) if length else b""

    def send_bytes(self, status, ctype, body):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def tickets(self, method):
        """Tickets de carburant du téléphone (ticket.js, tickets_boite.py) : vrai si traité ici."""
        path = urlparse(self.path).path
        if path not in ("/api/tickets", "/api/tickets/etat", "/api/chiffres"):
            return False
        if not self.guard(path):
            return True
        import base64
        import alerte_appareils as AA
        import orbiscan_tunnel as T

        try:
            if path == "/api/tickets" and method == "POST":
                data = json.loads(self.read_limited(40 * 1024 * 1024) or b"{}")
                packets = {str(pc): base64.b64decode(str(blob), validate=True)
                           for pc, blob in (data.get("packets") or {}).items()}
                state = T.TUNNEL.mail.post(AA.device_id(self.headers.get("X-Appareil")), data.get("id"), packets)
                self.send_json({"id": data.get("id"), "state": state})
            elif path == "/api/chiffres" and method == "GET":
                # Boîtes des chiffres de ce téléphone (une par PC jumelé) : paquets chiffrés.
                boxes = (parse_qs(urlparse(self.path).query).get("boxes") or [""])[0].split(",")[:8]
                with T.TUNNEL.lock:
                    got = T.TUNNEL.figures.get(boxes)
                self.send_json({"boxes": {b: base64.b64encode(v).decode() for b, v in got.items()}})
            elif path == "/api/tickets/etat" and method == "GET":
                ids = (parse_qs(urlparse(self.path).query).get("ids") or [""])[0].split(",")[:50]
                self.send_json({"states": T.TUNNEL.mail.states(ids)})
            else:
                self.send_error(405)
        except PermissionError as error:
            self.send_json({"error": str(error)}, 429)
        except (ValueError, TypeError, AttributeError):
            self.send_json({"error": "ticket invalide"}, 400)
        return True

    def orbiscan(self, method):
        """Orbiscan dans Orbismini (orbiscan_tunnel.py) : vrai si la requête est traitée ici."""
        path = urlparse(self.path).path
        if path == "/orbiscan-pc":
            # Page de Sylvian : PC retenus, remise à zéro.
            if self.guard(path):
                import orbiscan_pc

                self.send_bytes(200, "text/html; charset=utf-8", orbiscan_pc.ADMIN_PAGE.encode("utf-8"))
            return True
        if not (path.startswith("/api/orbiscan/") or path == "/orbiscan" or path.startswith("/orbiscan/")):
            return False
        import base64
        import orbiscan_tunnel as T

        # Relais des PC : sans mot de passe d'Orbismini (le PC s'identifie par son secret).
        if path.startswith("/api/orbiscan/relais/"):
            if method != "POST":
                self.send_error(405)
                return True
            try:
                data = json.loads(self.read_limited(T.MAX_BODY * 2) or b"{}")
                if path == "/api/orbiscan/relais/attente":
                    import orbiscan_pc

                    # PC retenu à sa première venue (GitHub) : ni autre secret, ni autre clé ensuite.
                    T.validate(data.get("pc"), data.get("key") or {}, data.get("secret"))
                    orbiscan_pc.STORE.check(data.get("pc"), data.get("name"), data.get("secret"), data.get("key"))
                    pc, mail = data.get("pc"), T.TUNNEL.mail
                    # Relais qui sait relever les tickets de carburant : réveillé aussi pour eux.
                    wake = (lambda: bool(mail.waiting(pc))) if data.get("tickets") else None
                    out = T.TUNNEL.relay_wait(pc, data.get("name"), data.get("key") or {},
                                              data.get("secret"), self.client_ip(), wake=wake)
                    reply = {"requests": out}
                    if wake:
                        with T.TUNNEL.lock:
                            reply["tickets"] = mail.waiting(pc, mark=True)
                    self.send_json(reply)
                elif path == "/api/orbiscan/relais/chiffres":
                    # Chiffres d'Orbis pour un téléphone : paquet chiffré, gardé dans sa boîte.
                    if not T.TUNNEL.authentic(data.get("pc"), data.get("secret")):
                        raise PermissionError("relais inconnu")
                    with T.TUNNEL.lock:
                        T.TUNNEL.figures.put(data.get("box"), base64.b64decode(str(data.get("blob") or ""), validate=True))
                    self.send_json({"ok": True})
                elif path in ("/api/orbiscan/relais/ticket", "/api/orbiscan/relais/ticket-range"):
                    # Ticket de carburant : réservé par ce relais (paquet scellé pour lui), ou rangé par Orbis.
                    pc = data.get("pc")
                    if not T.TUNNEL.authentic(pc, data.get("secret")):
                        raise PermissionError("relais inconnu")
                    try:
                        if path.endswith("/ticket"):
                            blob = T.TUNNEL.mail.lease(pc, data.get("id"))
                            self.send_json({"id": data.get("id"), "blob": base64.b64encode(blob).decode()})
                        else:
                            self.send_json({"ok": T.TUNNEL.mail.filed(pc, data.get("id"))})
                    except LookupError as error:
                        self.send_json({"error": str(error)}, 404)
                elif path == "/api/orbiscan/relais/reponse":
                    T.TUNNEL.relay_answer(data.get("pc"), data.get("secret"), data.get("id"),
                                          int(data.get("status") or 500), data.get("type"),
                                          base64.b64decode(data.get("body") or ""))
                    self.send_json({"ok": True})
                else:
                    self.send_error(404)
            except PermissionError as error:
                self.send_json({"error": str(error)}, 403)
            except (ValueError, TypeError, AttributeError):
                self.send_json({"error": "demande invalide"}, 400)
            return True

        # Téléphone : session d'Orbismini obligatoire.
        if not self.guard(path):
            return True
        ip = self.client_ip()
        if path == "/api/orbiscan/pc-admin" and method == "POST":
            # Sylvian : liste des PC retenus et remise à zéro (code ORBISCAN_ADMIN).
            import orbiscan_pc

            try:
                data = json.loads(self.read_limited(10_000) or b"{}")
                if data.get("reset"):
                    orbiscan_pc.STORE.reset(data.get("code"), str(data["reset"]))
                self.send_json({"pcs": orbiscan_pc.STORE.listing(data.get("code"))})
            except PermissionError as error:
                self.send_json({"error": str(error)}, 403)
            except (ValueError, TypeError):
                self.send_json({"error": "demande invalide"}, 400)
            return True
        if path == "/api/orbiscan/peers":
            self.send_json({"peers": T.TUNNEL.peers(ip)})
            return True
        m = re.fullmatch(r"/api/orbiscan/pc/([\w-]{8,40})(/.*)", path)
        if m:
            try:
                body = self.read_limited(T.MAX_BODY) if method == "POST" else b""
            except ValueError:
                self.send_json({"error": "trop lourd"}, 413)
                return True
            self.send_bytes(*T.TUNNEL.call(ip, m.group(1), method, m.group(2),
                                           self.headers.get("Content-Type", ""), body))
            return True
        if method != "GET":
            self.send_error(405)
            return True
        # Page Orbiscan du PC (la même que sur l'icône), servie par le premier PC du magasin.
        peers = T.TUNNEL.peers(ip)
        if not peers:
            self.send_bytes(200, "text/html; charset=utf-8", T.NO_PC_PAGE.encode("utf-8"))
            return True
        home = peers[0]["pc"]
        sub = path[len("/orbiscan"):] or "/"
        status, ctype, body = T.TUNNEL.call(ip, home, "GET", "/t" if sub == "/" else sub)
        if status == 200 and ctype.startswith("text/html"):
            body = T.page(body.decode("utf-8"), home).encode("utf-8")
        self.send_bytes(status, ctype, body)
        return True

    def do_POST(self):
        if self.orbis_events("POST") or self.tickets("POST") or self.orbiscan("POST"):
            return
        if urlparse(self.path).path == "/api/scan/identify":
            # Scanner de pièces : photos (JPEG en base64) → pièces possibles (pieces_scan.py).
            if not self.guard("/api/scan/identify"):
                return
            import base64
            import pieces_scan

            try:
                length = int(self.headers.get("Content-Length") or 0)
                if length > 15_000_000:
                    raise ValueError("Photos trop lourdes.")
                body = json.loads(self.rfile.read(length) or b"{}")
                photos = [(str(p.get("side") or "face"), base64.b64decode(str(p.get("data") or ""), validate=True))
                          for p in (body.get("photos") or [])[:2] if isinstance(p, dict)]
                return self.send_json(pieces_scan.identify(pieces_scan.FOLDER, photos))
            except (ValueError, TypeError) as error:
                return self.send_json({"error": str(error)[:300]}, 400)
        if urlparse(self.path).path == "/api/proposition":
            # « Envoyer au client » (application iPhone) : la Proposition de rachat d’Orbis en PDF.
            if not self.guard("/api/proposition"):
                return
            import proposition

            try:
                pdf = proposition.make(json.loads(self.read_limited(2_000_000) or b"{}"))
                return self.send_bytes(200, "application/pdf", pdf)
            except LookupError as error:
                return self.send_json({"error": str(error)[:300]}, 503)
            except ImportError:
                return self.send_json({"error": "Fabrication du PDF indisponible (reportlab absent sur Render)."}, 503)
            except (ValueError, TypeError) as error:
                return self.send_json({"error": str(error)[:300]}, 400)
        if urlparse(self.path).path == "/api/apns":
            # Application iPhone : jeton de notification de ce téléphone (apns.py, éteint par défaut).
            if not self.guard("/api/apns"):
                return
            import apns
            import alerte_appareils as AA

            if not apns.enabled():
                return self.send_json({"enabled": False})
            did = AA.device_id(self.headers.get("X-Appareil"))
            if not did:
                return self.send_json({"error": "Téléphone non reconnu."}, 400)
            try:
                length = min(int(self.headers.get("Content-Length") or 0), 4096)
                body = json.loads(self.rfile.read(length) or b"{}")
                AA.STORE.set_apns(did, body.get("token"), body.get("env"), body.get("nom"))
                return self.send_json({"enabled": True})
            except (ValueError, TypeError, AttributeError) as error:
                return self.send_json({"error": str(error)[:200]}, 400)
            except PermissionError as error:
                return self.send_json({"error": str(error)[:200]}, 503)
        if urlparse(self.path).path == "/api/alert":
            # Réglage des seuils (iPhone ou Orbis) : état fusionné, le plus récent l’emporte.
            if not self.guard("/api/alert"):
                return
            import alerte

            try:
                length = min(int(self.headers.get("Content-Length") or 0), 50_000)
                body = json.loads(self.rfile.read(length) or b"{}")
                mine = self.phone_alert(body)
                if mine is not None:
                    return self.send_json(mine)
                alerte.update(body, ALERT_KEY)
                return self.send_json(alert_view(self.authorized()))
            except (ValueError, TypeError) as error:
                return self.send_json({"error": str(error)[:200]}, 400)
            except PermissionError as error:
                return self.send_json({"error": str(error)[:200]}, 503)
        if urlparse(self.path).path in ("/api/alert/lier", "/api/alert/detacher"):
            # Téléphone relié à l’alerte d’Orbis (code de Sylvian) ou rendu à sa propre alerte.
            if not self.guard("/api/alert/lier"):
                return
            import alerte_appareils as AA

            did = AA.device_id(self.headers.get("X-Appareil"))
            if not did:
                return self.send_json({"error": "Téléphone non reconnu, recharge la page."}, 400)
            try:
                length = min(int(self.headers.get("Content-Length") or 0), 4096)
                body = json.loads(self.rfile.read(length) or b"{}")
                if urlparse(self.path).path == "/api/alert/lier":
                    AA.STORE.link(did, body.get("code"))
                else:
                    AA.STORE.unlink(did)
                return self.send_json(self.phone_alert())
            except (ValueError, TypeError) as error:
                return self.send_json({"error": str(error)[:200]}, 400)
            except PermissionError as error:
                return self.send_json({"error": str(error)[:200]}, 403 if "Code" in str(error) else 503)
        if urlparse(self.path).path != "/login" or not PASSWORD:
            return self.send_error(404)
        length = min(int(self.headers.get("Content-Length") or 0), 4096)
        form = parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
        given = (form.get("password") or [""])[0]
        if not hmac.compare_digest(given.encode(), PASSWORD.encode()):
            time.sleep(1)  # Freine les essais en série.
            return self.send_login(error="Mot de passe incorrect.")
        self.send_response(303)
        self.set_session(session_token(), SESSION_DAYS * 86400)
        self.send_header("Location", "/")
        self.end_headers()

    def do_HEAD(self):
        path = self.path.split("?")[0]
        if not public(path):
            return self.send_error(404)
        if not (self.authorized() or path in OPEN_FILES):
            self.send_response(401)
            self.end_headers()
            return None
        return super().do_HEAD()

    def do_GET(self):
        if self.orbis_events("GET") or self.tickets("GET") or self.orbiscan("GET"):
            return
        url = urlparse(self.path)
        if url.path == "/logout":
            self.send_response(303)
            self.set_session("", 0)
            self.send_header("Location", "/")
            self.end_headers()
            return
        if url.path == "/login":
            if self.authorized():
                self.send_response(303)
                self.send_header("Location", "/")
                self.end_headers()
                return
            return self.send_login(200)
        if not self.guard(url.path):
            return
        if url.path == "/api/alert":
            try:
                mine = self.phone_alert()
            except PermissionError as error:
                return self.send_json({"error": str(error)[:200]}, 503)
            return self.send_json(mine if mine is not None else alert_view(self.authorized()))
        if url.path in ("/api/scan/state", "/api/scan/search", "/api/scan/coin"):
            # Scanner de pièces : clés présentes, recherche dans Numista, fiche d'une pièce.
            import pieces_scan

            q = {k: v[0] for k, v in parse_qs(url.query).items()}
            try:
                if url.path == "/api/scan/state":
                    return self.send_json(pieces_scan.keys_state())
                if url.path == "/api/scan/search":
                    return self.send_json(dict(results=pieces_scan.search(
                        pieces_scan.FOLDER, q.get("q"), q.get("country"), q.get("year"))))
                return self.send_json(pieces_scan.details(pieces_scan.FOLDER, q.get("id", ""), q.get("year")))
            except ValueError as error:
                return self.send_json({"error": str(error)[:300]}, 400)
        if url.path == "/api/alert/check":
            import alerte

            import alerte_appareils as AA

            got = []
            loader = lambda: got[0] if got else got.append(alert_price()) or got[0]  # cours lu une fois
            for run in (lambda: alerte.check(loader, ALERT_KEY), lambda: AA.STORE.check(loader)):
                try:
                    run()
                except Exception:
                    pass
            return self.send_json({"ok": True})
        if url.path in ROUTES:
            try:
                data = ROUTES[url.path](parse_qs(url.query))
                status = 200
            except Exception as error:
                data = {"error": str(error)[:300]}
                status = 503
            payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return
        if not public(url.path):
            return self.send_error(404)
        return super().do_GET()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print("Ouvrez http://localhost:" + str(port) + " dans votre navigateur.")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
