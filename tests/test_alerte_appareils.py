"""Alerte propre à chaque téléphone (alerte_appareils.py), GitHub simulé."""

import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import alerte as A
import alerte_appareils as AA
import orbiscan_pc as P
from test_orbiscan_pc import FakeGitHub

PHONE1, PHONE2 = "a" * 32, "0123456789abcdef" * 2


class FakeGitHubAlerts(FakeGitHub):
    def __call__(self, method, url, token, body=None):
        url = url.replace("heads/alertes", "heads/orbiscan-pc").replace("alertes.json", "pc.json")
        if body and body.get("branch") == "alertes":
            body = dict(body, branch="orbiscan-pc")
        return super().__call__(method, url, token, body)


class DeviceAlertTests(unittest.TestCase):
    def setUp(self):
        self.gh = FakeGitHubAlerts()
        for target, value in ((P, "http"), ):
            p = patch.object(target, value, self.gh)
            p.start()
            self.addCleanup(p.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        A.FILE = os.path.join(self.tmp.name, "etat.json")
        A._state = None
        A._sent.clear()
        self.sent = []
        self.post = lambda topic, title, body: self.sent.append((topic, title))
        self.now = datetime.now(timezone.utc).isoformat()

    def store(self):
        return AA.Store(token="jeton-github")

    def test_each_phone_has_its_own_alert_and_channel(self):
        s = self.store()
        d1, d2 = AA.device_id(PHONE1), AA.device_id(PHONE2)
        s.update(d1, dict(above=120000, updated="2026-11-15T10:00:00+00:00"))
        self.assertEqual(s.view(d1)["above"], 120000.0)
        self.assertNotIn("above", s.view(d2))                      # l'autre téléphone ne la voit pas
        self.assertNotEqual(s.view(d1)["channel"], s.view(d2)["channel"])
        s.update(d2, dict(below=100000, updated="2026-11-15T10:01:00+00:00"))
        self.assertEqual(s.check(lambda: (121000.0, self.now), self.post) and len(self.sent), 1)
        self.assertEqual(self.sent[0][0], s.view(d1)["channel"])   # seul le premier est prévenu
        self.assertNotIn("above", s.view(d1))
        self.assertEqual(s.view(d2)["below"], 100000.0)
        self.assertEqual(A.state().get("above"), None)             # l'alerte d'Orbis n'a pas bougé

    def test_kept_on_github_without_secret_or_channel(self):
        d1 = AA.device_id(PHONE1)
        self.store().update(d1, dict(move=2, updated="2026-11-15T10:00:00+00:00"))
        saved = self.gh.file
        self.assertNotIn(PHONE1, saved)
        self.assertNotIn(AA.channel(d1), saved)
        self.assertEqual(json.loads(saved)["devices"][d1]["state"]["move"], 2.0)
        again = self.store()                                         # Render redémarré
        self.assertEqual(again.view(d1)["move"], 2.0)
        # Un seuil retiré par ce téléphone reste retiré.
        again.update(d1, dict(updated="2026-11-15T11:00:00+00:00"))
        self.assertNotIn("move", self.store().view(d1))

    def test_link_to_orbis_needs_sylvians_code(self):
        s = self.store()
        d1 = AA.device_id(PHONE1)
        with patch.object(P.STORE, "admin", "code-de-sylvian"), patch.object(P.time, "sleep"):
            with self.assertRaises(PermissionError):
                s.link(d1, "mauvais")
            self.assertFalse(s.linked(d1))
            s.link(d1, "code-de-sylvian")
        self.assertTrue(self.store().linked(d1))
        s.unlink(d1)
        self.assertFalse(self.store().linked(d1))

    def test_bad_phone_id_and_refusal_without_github(self):
        self.assertIsNone(AA.device_id("court"))
        self.assertIsNone(AA.device_id("Z" * 32))
        with self.assertRaises(PermissionError):
            AA.Store(token="").view(AA.device_id(PHONE1))
        self.gh.down = True
        with self.assertRaises(PermissionError):
            self.store().update(AA.device_id(PHONE1), dict(above=120000, updated="2026-11-15T10:00:00+00:00"))


if __name__ == "__main__":
    unittest.main()
