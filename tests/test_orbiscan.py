"""Orbiscan dans Orbismini (orbiscan_tunnel.py) : rien sur disque, rien en clair, rien hors du
réseau du magasin, rien qui traîne."""

import base64
import builtins
import threading
import time
import unittest
from unittest.mock import patch

import orbiscan_tunnel as T

KEY = {"n": base64.urlsafe_b64encode(b"\xc5" * 256).rstrip(b"=").decode(), "e": "AQAB"}
SHOP, HOME = "81.250.10.20", "90.1.2.3"
SEALED_BODY = T.MAGIC + b"\x01\x00" + b"x" * 400


class Clock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


def relay(tunnel, pc="pc-magasin", ip=SHOP, answer=(200, "application/json", b'{"ok": true}'), seen=None):
    """Faux relais : une relève, puis répond à chaque demande reçue."""
    def run():
        for req in tunnel.relay_wait(pc, "Nancy", KEY, "secret-du-relais-123456", ip, wait=2):
            if seen is not None:
                seen.append(req)
            tunnel.relay_answer(pc, "secret-du-relais-123456", req["id"], *answer)
    t = threading.Thread(target=run, daemon=True)
    t.start()
    return t


class AddressTests(unittest.TestCase):
    """Adresse vue par Orbismini : une fausse adresse envoyée par l'appelant ne compte pas."""

    def ip(self, headers):
        import server

        h = server.Handler.__new__(server.Handler)
        h.headers, h.client_address = headers, ("127.0.0.1", 1)
        return h.client_ip()

    def test_forged_forwarded_address_ignored(self):
        # Ce que Render transmet quand l'appelant ajoute lui-même un faux début (relevé le 15/11/2026).
        real = {"X-Forwarded-For": "81.250.10.20,86.225.248.74, 172.71.232.16, 10.31.60.5",
                "True-Client-IP": "86.225.248.74", "CF-Connecting-IP": "86.225.248.74"}
        self.assertEqual(self.ip(real), "86.225.248.74")
        self.assertEqual(self.ip({"X-Forwarded-For": SHOP}), "127.0.0.1")      # jamais X-Forwarded-For
        self.assertEqual(self.ip({"CF-Connecting-IP": "86.225.248.74"}), "86.225.248.74")


class TunnelTests(unittest.TestCase):
    def setUp(self):
        self.tunnel = T.Tunnel()
        self.tunnel.relay_wait("pc-magasin", "Nancy", KEY, "secret-du-relais-123456", SHOP, wait=0)

    def test_only_phones_on_the_shop_connection_see_the_pc(self):
        self.assertEqual([p["name"] for p in self.tunnel.peers(SHOP)], ["Nancy"])
        self.assertEqual(self.tunnel.peers(HOME), [])           # 5G, autre Wi-Fi : rien
        status, _, _ = self.tunnel.call(HOME, "pc-magasin", "GET", "/api/ping")
        self.assertEqual(status, 404)
        self.assertTrue(T.same_network("2a01:cb00:1:2::5", "2a01:cb00:1:2:aaaa::9"))
        self.assertFalse(T.same_network("2a01:cb00:1:2::5", "2a01:cb00:1:3::5"))
        self.assertFalse(T.same_network("81.250.10.20", "2a01:cb00:1:2::5"))

    def test_round_trip_through_the_relay(self):
        seen = []
        t = relay(self.tunnel, seen=seen)
        self.assertEqual(self.tunnel.call(SHOP, "pc-magasin", "GET", "/api/ping", wait=3),
                         (200, "application/json", b'{"ok": true}'))
        t.join(3)
        self.assertEqual((seen[0]["method"], seen[0]["path"]), ("GET", "/api/ping"))
        self.assertEqual(self.tunnel.held_bytes(), 0)            # rien ne reste en mémoire

    def test_closed_list_of_addresses(self):
        for method, path in (("GET", "/api/session"), ("GET", "/api/poll/abcdefghijkl"),
                             ("GET", "/api/image/abcdefghijkl/recto"), ("GET", "/api/orbis/photo/abcdefghijkl"),
                             ("POST", "/api/orbis/session"), ("DELETE", "/api/pairing"), ("GET", "/../secret")):
            self.assertEqual(self.tunnel.call(SHOP, "pc-magasin", method, path)[0], 403, path)
        self.assertTrue(T.allowed("POST", "/api/upload/abcdefghijkl/recto"))
        self.assertTrue(T.allowed("GET", "/t"))

    def test_plain_photo_refused(self):
        path = "/api/upload/abcdefghijkl/recto"
        jpeg = b"\xff\xd8\xff\xe0" + b"0" * 100
        self.assertEqual(self.tunnel.call(SHOP, "pc-magasin", "POST", path, "image/jpeg", jpeg)[0], 415)
        self.assertEqual(self.tunnel.call(SHOP, "pc-magasin", "POST", path, T.SEALED, jpeg)[0], 415)
        seen = []
        t = relay(self.tunnel, seen=seen)
        self.assertEqual(self.tunnel.call(SHOP, "pc-magasin", "POST", path, T.SEALED, SEALED_BODY, wait=3)[0], 200)
        t.join(3)
        self.assertEqual(base64.b64decode(seen[0]["body"]), SEALED_BODY)   # transmis tel quel, chiffré

    def test_nothing_written_to_disk(self):
        real_open = builtins.open

        def no_write(file, mode="r", *a, **k):
            if any(c in mode for c in "wax+"):
                raise AssertionError("écriture sur disque : %s" % file)
            return real_open(file, mode, *a, **k)

        with patch.object(builtins, "open", no_write):
            t = relay(self.tunnel)
            self.tunnel.call(SHOP, "pc-magasin", "POST", "/api/upload/abcdefghijkl/verso", T.SEALED, SEALED_BODY, wait=3)
            t.join(3)

    def test_everything_forgotten_after_two_minutes(self):
        clock = Clock()
        tunnel = T.Tunnel(clock)
        tunnel.relay_wait("pc-magasin", "Nancy", KEY, "secret-du-relais-123456", SHOP, wait=0)
        done = []
        threading.Thread(target=lambda: done.append(
            tunnel.call(SHOP, "pc-magasin", "POST", "/api/upload/abcdefghijkl/recto", T.SEALED, SEALED_BODY, wait=0.2)),
            daemon=True).start()
        time.sleep(0.05)
        clock.t += 1
        time.sleep(0.4)
        self.assertEqual(done[0][0], 504)                      # le PC n'a pas répondu
        self.assertEqual(tunnel.held_bytes(), 0)               # la photo chiffrée est déjà effacée
        clock.t += T.KEEP + 1
        self.assertEqual(tunnel.peers(SHOP), [])               # PC oublié lui aussi
        self.assertEqual(tunnel.pcs, {})

    def test_another_relay_cannot_take_over_a_live_pc(self):
        with self.assertRaises(PermissionError):
            self.tunnel.relay_wait("pc-magasin", "Pirate", KEY, "un-autre-secret-123456789", SHOP, wait=0)
        with self.assertRaises(PermissionError):
            self.tunnel.relay_answer("pc-magasin", "un-autre-secret-123456789", "x", 200, "", b"")

    def test_page_served_under_orbiscan(self):
        html = T.page('<html><head><link rel="icon" href="/icon-192.png"></head><img src="/logo-orbis.png">', "pc-1")
        self.assertIn('src="/orbiscan-shim.js"', html)
        self.assertIn('href="/orbiscan/icon-192.png"', html)
        self.assertIn('src="/orbiscan/logo-orbis.png"', html)
        self.assertLess(html.index("orbiscan-shim.js"), html.index("logo-orbis"))


if __name__ == "__main__":
    unittest.main()
