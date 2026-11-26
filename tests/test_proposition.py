"""Proposition de rachat envoyée depuis le téléphone (proposition.py, route /api/proposition)."""

import io
import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import proposition as PR

try:
    import reportlab  # noqa: F401

    HAS_REPORTLAB = True
except ImportError:
    HAS_REPORTLAB = False

AGENCIES = {"Nancy": dict(company="CNDO Nancy", address="1 rue de l’Essai, 54000 Nancy", phone="03 00 00 00 00",
                          email="nancy@exemple.fr")}


def row(name, gross, tax, net):
    return dict(name=name, quantity="2 unité(s)", count=2, mode="Boursable", reference=610, percent=3.5,
                productId="napoleon", result=dict(gross=gross, tax=tax, net=net, taxLabel="TMP", taxRate=0.115,
                                                  taxBase=gross))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        path = Path(self.tmp.name) / "agences.json"
        path.write_text(json.dumps(AGENCIES), encoding="utf-8")
        p = patch.object(PR, "AGENCIES", path)
        p.start()
        self.addCleanup(p.stop)


@unittest.skipUnless(HAS_REPORTLAB, "reportlab absent (requirements.txt)")
class PropositionTests(Base):
    def body(self, **more):
        return dict(dict(agence="Nancy", contact="Sylvian", client=dict(name="DUPONT Jean", phone="06 12 34 56 78"),
                         rows=[row("Napoléon 20 F", "1160.00", "133.40", "1026.60")]), **more)

    def test_pdf_made(self):
        pdf = PR.make(self.body(), now=datetime(2026, 11, 26, 15, 30))
        self.assertTrue(pdf.startswith(b"%PDF"))

    def test_refused(self):
        for bad in (self.body(rows=[]), self.body(client=dict(name=" ")), "texte"):
            with self.assertRaises(ValueError):
                PR.make(bad)
        with self.assertRaises(LookupError):
            PR.make(self.body(agence="Calais"))    # mentions pas encore fournies

    def test_route(self):
        import server

        def call(body):
            h = server.Handler.__new__(server.Handler)
            raw = json.dumps(body).encode()
            h.path = "/api/proposition"
            h.headers = {"Content-Length": str(len(raw))}
            h.rfile = io.BytesIO(raw)
            out = []
            h.send_json = lambda data, status=200: out.append((status, data))
            h.send_bytes = lambda status, ctype, data: out.append((status, ctype, data[:4]))
            h.guard = lambda path: True
            h.do_POST()
            return out[0]

        self.assertEqual(call(self.body()), (200, "application/pdf", b"%PDF"))
        self.assertEqual(call(self.body(agence="Troyes"))[0], 503)
        self.assertEqual(call(self.body(rows=[]))[0], 400)


class AgencyFileTests(Base):
    def test_incomplete_agencies_ignored(self):
        Path(PR.AGENCIES).write_text(json.dumps({"Nancy": AGENCIES["Nancy"], "Troyes": {"company": ""}}), encoding="utf-8")
        self.assertEqual(list(PR.agencies()), ["Nancy"])

    def test_not_public(self):
        import server

        for route in ("/agences-proposition.json", "/proposition_pdf.py", "/proposition.py"):
            self.assertFalse(server.public(route), route)
        self.assertTrue(server.public("/logo-impression.jpg"))
