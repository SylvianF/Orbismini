"""PC d'Orbiscan retenus pour de bon (orbiscan_pc.py), GitHub simulé."""

import base64
import json
import unittest
from unittest.mock import patch

import orbiscan_pc as P

KEY = {"n": "AAAA" * 90, "e": "AQAB"}
OTHER_KEY = {"n": "BBBB" * 90, "e": "AQAB"}


class FakeGitHub:
    def __init__(self):
        self.file, self.sha, self.branch, self.calls, self.down = None, 0, False, [], False

    def __call__(self, method, url, token, body=None):
        self.calls.append((method, url, body))
        assert token == "jeton-github"
        if self.down:
            return 503, {}
        if "/git/ref/heads/orbiscan-pc" in url:
            return (200, {}) if self.branch else (404, {})
        if "/git/ref/heads/main" in url:
            return 200, {"object": {"sha": "abc"}}
        if url.endswith("/git/refs"):
            self.branch = True
            return 201, {}
        if method == "GET":
            if self.file is None:
                return 404, {}
            return 200, {"content": base64.b64encode(self.file.encode()).decode(), "sha": str(self.sha)}
        if method == "PUT":
            assert body["branch"] == "orbiscan-pc" and self.branch
            if self.file is not None and body.get("sha") != str(self.sha):
                return 409, {}
            self.file, self.sha = base64.b64decode(body["content"]).decode(), self.sha + 1
            return 200, {"content": {"sha": str(self.sha)}}
        return 404, {}


class PinTests(unittest.TestCase):
    def setUp(self):
        self.gh = FakeGitHub()
        p = patch.object(P, "http", self.gh)
        p.start()
        self.addCleanup(p.stop)

    def store(self):
        return P.Store(token="jeton-github", admin="code-de-sylvian")

    def test_first_visit_pins_then_only_same_secret_and_key(self):
        s = self.store()
        self.assertTrue(s.check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY))
        saved = json.loads(self.gh.file)
        self.assertNotIn("secret-du-pc-nancy-0123", self.gh.file)           # empreinte seulement
        self.assertEqual(saved["pc-nancy-01"]["secret"], P.digest("secret-du-pc-nancy-0123"))
        self.assertFalse(s.check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY))
        with self.assertRaises(PermissionError):
            s.check("pc-nancy-01", "Nancy", "un-autre-secret-0123456789", KEY)
        with self.assertRaises(PermissionError):
            s.check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", OTHER_KEY)

    def test_survives_a_restart_of_render(self):
        self.store().check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY)
        again = self.store()                                                 # Render redémarré
        with self.assertRaises(PermissionError):
            again.check("pc-nancy-01", "Pirate", "un-autre-secret-0123456789", OTHER_KEY)
        self.assertFalse(again.check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY))

    def test_refuses_when_it_cannot_remember(self):
        with self.assertRaises(PermissionError):
            P.Store(token="", admin="x").check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY)
        self.gh.down = True
        with self.assertRaises(PermissionError):
            self.store().check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY)

    def test_reset_only_with_sylvians_code(self):
        s = self.store()
        s.check("pc-nancy-01", "Nancy", "secret-du-pc-nancy-0123", KEY)
        with patch.object(P.time, "sleep"):
            with self.assertRaises(PermissionError):
                s.reset("mauvais", "pc-nancy-01")
            with self.assertRaises(PermissionError):
                P.Store(token="jeton-github", admin="").listing("")
        self.assertEqual([p["name"] for p in s.listing("code-de-sylvian")], ["Nancy"])
        self.assertTrue(s.reset("code-de-sylvian", "pc-nancy-01"))
        self.assertEqual(s.listing("code-de-sylvian"), [])
        self.assertTrue(s.check("pc-nancy-01", "Nancy", "nouveau-secret-apres-reinstall", OTHER_KEY))


if __name__ == "__main__":
    unittest.main()
