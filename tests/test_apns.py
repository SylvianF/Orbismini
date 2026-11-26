"""Notifications de l’application iPhone (apns.py) : éteintes par défaut, ntfy inchangé."""

import io
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import alerte as A
import alerte_appareils as AA
import apns
import orbiscan_pc as P
from test_alerte_appareils import FakeGitHubAlerts

PHONE1, PHONE2 = "a" * 32, "0123456789abcdef" * 2
TOKEN1, TOKEN2 = "ab" * 32, "cd" * 32
ON = dict(ORBISMINI_APNS="1", APNS_KEY="clé", APNS_KEY_ID="ABCDEFGHIJ", APNS_TEAM_ID="TEAM123456",
          APNS_TOPIC="fr.cndo.orbismini")

try:
    import cryptography  # noqa: F401

    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False


class Base(unittest.TestCase):
    def setUp(self):
        self.gh = FakeGitHubAlerts()
        p = patch.object(P, "http", self.gh)
        p.start()
        self.addCleanup(p.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        A.FILE = os.path.join(self.tmp.name, "etat.json")
        A._state = None
        A._sent.clear()
        self.ntfy, self.apple = [], []
        self.post = lambda topic, title, body: self.ntfy.append((topic, title, body))
        self.now = datetime.now(timezone.utc).isoformat()
        apns._jwt[:] = [0.0, ""]
        env = patch.dict(os.environ, {k: "" for k in ON})
        env.start()
        self.addCleanup(env.stop)

    def apple_post(self, status=200, reason=""):
        def post(url, headers, payload):
            self.apple.append((url, headers, json.loads(payload)))
            return status, reason
        return post


class SwitchTests(Base):
    def test_off_by_default(self):
        self.assertFalse(apns.enabled())
        self.assertEqual(apns.send([(TOKEN1, "production")], "t", "b", self.apple_post()), [])
        self.assertEqual(self.apple, [])

    def test_needs_switch_and_full_key(self):
        with patch.dict(os.environ, dict(ON, ORBISMINI_APNS="0")):
            self.assertFalse(apns.enabled())
        with patch.dict(os.environ, dict(ON, APNS_KEY="")):
            self.assertFalse(apns.enabled())
        with patch.dict(os.environ, ON):
            self.assertTrue(apns.enabled())

    def test_token_checked(self):
        self.assertEqual(apns.clean_token(TOKEN1.upper(), None), (TOKEN1, "production"))
        self.assertEqual(apns.clean_token(TOKEN1, "sandbox"), (TOKEN1, "sandbox"))
        for bad in ("", "xyz", "ab" * 10):
            with self.assertRaises(ValueError):
                apns.clean_token(bad, "production")
        with self.assertRaises(ValueError):
            apns.clean_token(TOKEN1, "autre")


class DeviceTests(Base):
    def store(self):
        return AA.Store(token="jeton-github")

    def test_phone_alert_goes_to_ntfy_and_app(self):
        s, d1 = self.store(), AA.device_id(PHONE1)
        s.update(d1, dict(above=120000, updated="2026-11-15T10:00:00+00:00"))
        s.set_apns(d1, TOKEN1, "sandbox")
        with patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"):
            s.check(lambda: (121000.0, self.now), self.post, self.apple_post())
        self.assertEqual(len(self.ntfy), 1)
        self.assertEqual(len(self.apple), 1)
        url, headers, payload = self.apple[0]
        self.assertEqual(url, "https://api.sandbox.push.apple.com/3/device/" + TOKEN1)
        self.assertEqual(headers["apns-topic"], "fr.cndo.orbismini")
        self.assertEqual(headers["authorization"], "bearer jeton")
        self.assertEqual(payload["aps"]["alert"]["title"], self.ntfy[0][1])   # même texte que ntfy
        self.assertEqual(payload["aps"]["alert"]["body"], self.ntfy[0][2])
        self.assertEqual(payload["aps"]["sound"], "orbismini.caf")      # son choisi par Sylvian

    def test_switched_off_ntfy_unchanged_and_nothing_to_apple(self):
        s, d1 = self.store(), AA.device_id(PHONE1)
        s.update(d1, dict(above=120000, updated="2026-11-15T10:00:00+00:00"))
        s.set_apns(d1, TOKEN1, "production")
        s.check(lambda: (121000.0, self.now), self.post, self.apple_post())
        self.assertEqual(len(self.ntfy), 1)
        self.assertEqual(self.apple, [])

    def test_apple_failure_never_blocks_ntfy(self):
        s, d1 = self.store(), AA.device_id(PHONE1)
        s.update(d1, dict(below=100000, updated="2026-11-15T10:00:00+00:00"))
        s.set_apns(d1, TOKEN1, "production")

        def broken(url, headers, payload):
            raise OSError("Apple injoignable")
        with patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"):
            s.check(lambda: (99000.0, self.now), self.post, broken)
        self.assertEqual(len(self.ntfy), 1)

    def test_token_moves_with_phone_and_rejected_token_forgotten(self):
        s, d1, d2 = self.store(), AA.device_id(PHONE1), AA.device_id(PHONE2)
        s.set_apns(d1, TOKEN1, "production")
        s.set_apns(d2, TOKEN1, "production")      # même iPhone, nouvel identifiant
        self.assertEqual(s.apns_tokens(d1), [])
        self.assertEqual(s.apns_tokens(d2), [(TOKEN1, "production")])
        s.update(d2, dict(above=120000, updated="2026-11-15T10:00:00+00:00"))
        with patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"):
            s.check(lambda: (121000.0, self.now), self.post, self.apple_post(410, "Unregistered"))
        self.assertEqual(s.apns_tokens(d2), [])
        self.assertNotIn(TOKEN1, self.gh.file)

    def test_removed_with_empty_token(self):
        s, d1 = self.store(), AA.device_id(PHONE1)
        s.set_apns(d1, TOKEN1, "production")
        s.set_apns(d1, TOKEN2, "production")
        self.assertEqual(len(s.apns_tokens(d1)), 2)
        s.set_apns(d1, "", None)
        self.assertEqual(s.apns_tokens(d1), [])

    def test_common_orbis_alert_reaches_linked_phones(self):
        s, d1 = self.store(), AA.device_id(PHONE1)
        s.set_apns(d1, TOKEN1, "production")
        with patch.object(P.STORE, "admin_ok", lambda code: True):
            s.link(d1, "code")
        with patch.object(AA, "STORE", s), patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"), \
                patch.object(apns, "_post", self.apple_post()):
            import server  # noqa: F401  (inscrit apns_orbis)
            hit = dict(id="h1", dir="above", level=120000.0, price=121000.0, at=self.now)
            A.notify(dict(hits=[hit]), "clé-orbis", self.post)
        self.assertEqual(len(self.ntfy), 1)
        self.assertEqual(self.ntfy[0][0], A.channel("clé-orbis"))   # canal d’Orbis inchangé
        self.assertEqual([u for u, _, _ in self.apple], ["https://api.push.apple.com/3/device/" + TOKEN1])


class RouteTests(Base):
    def call(self, body, headers):
        import server

        h = server.Handler.__new__(server.Handler)
        raw = json.dumps(body).encode()
        h.path = "/api/apns"
        h.headers = dict(headers, **{"Content-Length": str(len(raw))})
        h.rfile = io.BytesIO(raw)
        out = []
        h.send_json = lambda data, status=200: out.append((status, data))
        h.guard = lambda path: True
        h.do_POST()
        return out[0]

    def test_route_says_off_and_stores_nothing(self):
        status, data = self.call({"token": TOKEN1}, {"X-Appareil": PHONE1})
        self.assertEqual((status, data), (200, {"enabled": False}))
        self.assertIsNone(self.gh.file)

    def test_route_stores_token_when_on(self):
        s = AA.Store(token="jeton-github")
        with patch.object(AA, "STORE", s), patch.dict(os.environ, ON):
            self.assertEqual(self.call({"token": TOKEN1, "env": "sandbox"}, {"X-Appareil": PHONE1}),
                             (200, {"enabled": True}))
            self.assertEqual(self.call({"token": "zz"}, {"X-Appareil": PHONE1})[0], 400)
            self.assertEqual(self.call({"token": TOKEN1}, {})[0], 400)
        self.assertEqual(s.apns_tokens(AA.device_id(PHONE1)), [(TOKEN1, "sandbox")])


class OrbisEventTests(Base):
    """Demandes de virement et transferts annoncés par Orbis : seuls les téléphones cochés reçoivent."""

    def phones(self):
        s, d1, d2 = AA.Store(token="jeton-github"), AA.device_id(PHONE1), AA.device_id(PHONE2)
        s.set_apns(d1, TOKEN1, "production", "Sylvian")
        s.set_apns(d2, TOKEN2, "production", "Magasin")
        return s, d1, d2

    def test_name_sealed_in_public_file_and_listed_for_orbis(self):
        with patch.dict(os.environ, GOLDAPP_PASSWORD="secret"):
            s, d1, d2 = self.phones()
            self.assertNotIn("Sylvian", self.gh.file)
            self.assertNotIn("Magasin", self.gh.file)
            listed = s.phones()
            self.assertEqual([x["nom"] for x in listed], ["Magasin", "Sylvian"])
            self.assertEqual({x["id"] for x in listed}, {d1[:16], d2[:16]})
            self.assertTrue(all(x["evenements"] == [] for x in listed))
            s.set_apns(d1, TOKEN1, "production")          # sans nom : inchangé
            self.assertIn("Sylvian", [x["nom"] for x in s.phones()])
            s.set_apns(d1, TOKEN1, "production", "")      # vide : retiré
            self.assertIn("", [x["nom"] for x in s.phones()])
        with patch.dict(os.environ, GOLDAPP_PASSWORD="autre"):
            self.assertEqual(AA.open_name(AA.seal_name("Rachel")), "Rachel")
            self.assertNotIn("Magasin", [x["nom"] for x in s.phones()])   # autre mot de passe : illisible

    def test_only_checked_phones_receive_and_once(self):
        s, d1, d2 = self.phones()
        s.set_events(d1[:16], ["virement", "transfert"])
        s.set_events(d2[:16], ["transfert"])
        with patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"):
            post = self.apple_post()
            self.assertEqual(s.event("virement", "v-12", "Nouvelle demande de virement", "Rachel, Nancy", post), 1)
            self.assertEqual(s.event("virement", "v-12", "Nouvelle demande de virement", "Rachel, Nancy", post), 0)
            self.assertEqual(s.event("transfert", "t-3", "Nouveau transfert", "Metz → Nancy", post), 2)
        urls = [u for u, _, _ in self.apple]
        self.assertEqual(urls[0], "https://api.push.apple.com/3/device/" + TOKEN1)
        self.assertEqual(sorted(urls[1:]), sorted("https://api.push.apple.com/3/device/" + t for t in (TOKEN1, TOKEN2)))
        self.assertEqual(self.apple[0][2]["aps"]["alert"], {"title": "Nouvelle demande de virement", "body": "Rachel, Nancy"})
        self.assertEqual(self.apple[0][2]["ecran"], "orbis")
        self.assertEqual(self.ntfy, [])

    def test_unchecking_and_bad_requests(self):
        s, d1, _ = self.phones()
        s.set_events(d1[:16], ["virement"])
        s.set_events(d1[:16], [])
        self.assertEqual([x["evenements"] for x in s.phones()], [[], []])
        for short, events in ((d1[:16], ["paie"]), ("0" * 16, ["virement"]), ("pas-un-id", []), (d1[:16], "virement"),
                              (d1[:16], ["achat"]), (d1[:16], ["virement:Nancy"]), (d1[:16], ["vente:N4ncy"])):
            with self.assertRaises(ValueError):
                s.set_events(short, events)
        with self.assertRaises(ValueError):
            s.event("paie", "x", "Titre", "")
        with self.assertRaises(ValueError):
            s.event("virement", "", "Titre", "")

    def test_switched_off_sends_nothing(self):
        s, d1, _ = self.phones()
        s.set_events(d1[:16], ["virement"])
        self.assertEqual(s.event("virement", "v-1", "Demande", "", self.apple_post()), 0)
        self.assertEqual(self.apple, [])
        with patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"):
            self.assertEqual(s.event("virement", "v-1", "Demande", "", self.apple_post()), 1)   # pas « déjà envoyée »


class TransactionTests(Base):
    """Achats et ventes : téléphones choisis ville par ville, la notification ouvre Chiffres."""

    def test_by_city_and_opens_chiffres(self):
        s, d1, d2 = AA.Store(token="jeton-github"), AA.device_id(PHONE1), AA.device_id(PHONE2)
        s.set_apns(d1, TOKEN1, "production", "Sylvian")
        s.set_apns(d2, TOKEN2, "production", "Magasin")
        listed = s.set_events(d1[:16], ["vente:Calais", "achat:Nancy", "achat:nancy", "virement", "achat:Troyes"])
        self.assertEqual([x["evenements"] for x in listed if x["id"] == d1[:16]],
                         [["virement", "achat:Nancy", "achat:Troyes", "vente:Calais"]])
        s.set_events(d2[:16], ["achat:Calais", "vente:Calais"])
        with patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"):
            post = self.apple_post()
            self.assertEqual(s.event("achat", "Nancy-81234", "Achat · Nancy",
                                     "1 240 € versés · marge théorique 180 €", post, city="NANCY"), 1)
            self.assertEqual(s.event("vente", "Calais-5512", "Vente · Calais", "860 €", post, city="Calais"), 2)
            self.assertEqual(s.event("vente", "Troyes-77", "Vente · Troyes", "", post, city="Troyes"), 0)
            with self.assertRaises(ValueError):
                s.event("achat", "x-1", "Achat", "", post)                 # ville obligatoire
        self.assertEqual(self.apple[0][0], "https://api.push.apple.com/3/device/" + TOKEN1)
        self.assertEqual(self.apple[0][2]["ecran"], "chiffres")
        self.assertEqual(self.apple[0][2]["aps"]["alert"]["body"], "1 240 € versés · marge théorique 180 €")
        self.assertEqual(len(self.apple), 3)

    def test_thin_spaces_kept_controls_removed(self):
        self.assertEqual(AA._short_text("1\u202f240 €\nversés\t· marge", 100),
                         "1\u202f240 € versés · marge")
        self.assertEqual(AA._short_text("  Achat  ·  Nancy ", 100), "Achat · Nancy")


class OrbisRouteTests(Base):
    def call(self, method, path, body=None, allowed=True):
        import server

        h = server.Handler.__new__(server.Handler)
        raw = json.dumps(body or {}).encode()
        h.path = path
        h.headers = {"Content-Length": str(len(raw))}
        h.rfile = io.BytesIO(raw)
        out = []
        h.send_json = lambda data, status=200: out.append((status, data))
        h.alert_allowed = lambda: allowed
        self.assertTrue(h.orbis_events(method))
        return out[0]

    def test_needs_orbis_key(self):
        with patch("time.sleep"):
            self.assertEqual(self.call("GET", "/api/orbis/telephones", allowed=False)[0], 403)
            self.assertEqual(self.call("POST", "/api/orbis/evenement", {"type": "virement"}, allowed=False)[0], 403)

    def test_list_check_and_announce(self):
        s = AA.Store(token="jeton-github")
        d1 = AA.device_id(PHONE1)
        s.set_apns(d1, TOKEN1, "production", "Sylvian")
        with patch.object(AA, "STORE", s), patch.dict(os.environ, ON), patch.object(apns, "jwt", lambda: "jeton"), \
                patch.object(apns, "_post", self.apple_post()):
            status, data = self.call("GET", "/api/orbis/telephones")
            self.assertEqual(status, 200)
            self.assertEqual(data["evenements"], ["virement", "transfert", "achat", "vente"])
            self.assertTrue(data["notifications"])
            self.assertEqual([(x["id"], x["evenements"]) for x in data["telephones"]], [(d1[:16], [])])
            status, data = self.call("POST", "/api/orbis/telephones", {"id": d1[:16], "evenements": ["virement"]})
            self.assertEqual((status, data["telephones"][0]["evenements"]), (200, ["virement"]))
            self.assertEqual(self.call("POST", "/api/orbis/evenement",
                                       {"type": "virement", "id": "v-7", "titre": "Nouvelle demande de virement",
                                        "texte": "Rachel, Nancy"}), (200, {"envoye": 1, "notifications": True}))
            self.assertEqual(self.call("POST", "/api/orbis/evenement", {"type": "?", "id": "1", "titre": "x"})[0], 400)
            self.call("POST", "/api/orbis/telephones", {"id": d1[:16], "evenements": ["vente:Nancy"]})
            self.assertEqual(self.call("POST", "/api/orbis/evenement",
                                       {"type": "vente", "ville": "Nancy", "id": "Nancy-9", "titre": "Vente · Nancy",
                                        "texte": "2 100 €"}), (200, {"envoye": 1, "notifications": True}))
            self.assertEqual(self.call("GET", "/api/orbis/evenement")[0], 405)
        self.assertEqual(len(self.apple), 2)

    def test_other_paths_untouched(self):
        import server

        h = server.Handler.__new__(server.Handler)
        h.path = "/api/orbiscan/peers"
        self.assertFalse(h.orbis_events("GET"))


@unittest.skipUnless(HAS_CRYPTO, "cryptography absent (requirements.txt)")
class JwtTests(Base):
    def test_es256_token_verifies(self):
        import base64
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

        key = ec.generate_private_key(ec.SECP256R1())
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption()).decode()
        for stored in (pem, pem.replace("\n", "\\n"), base64.b64encode(pem.encode()).decode()):
            apns._jwt[:] = [0.0, ""]
            with patch.dict(os.environ, dict(ON, APNS_KEY=stored)):
                token = apns.jwt(1_800_000_000)
            head, body, sig = token.split(".")
            pad = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
            self.assertEqual(json.loads(pad(head)), {"alg": "ES256", "kid": "ABCDEFGHIJ"})
            self.assertEqual(json.loads(pad(body)), {"iss": "TEAM123456", "iat": 1_800_000_000})
            raw = pad(sig)
            der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
            key.public_key().verify(der, (head + "." + body).encode(), ec.ECDSA(hashes.SHA256()))
        with patch.dict(os.environ, dict(ON, APNS_KEY=pem)):
            self.assertEqual(apns.jwt(1_800_000_000 + 60), token)        # gardé 40 minutes


if __name__ == "__main__":
    unittest.main()
