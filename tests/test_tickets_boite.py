"""Tickets de carburant : boîte aux lettres d'Orbismini (tickets_boite.py)."""

import threading
import unittest

import tickets_boite as B

PC1, PC2 = "pc-troyes-01", "pc-sylvian-01"
BLOB = B.MAGIC + b"\x01\x00" + b"x" * 300


class Clock:
    def __init__(self):
        self.t = 1_800_000_000.0

    def __call__(self):
        return self.t


class MailboxTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.box = B.Mailbox(threading.Condition(), self.clock)

    def test_first_pc_files_it_and_both_forget(self):
        self.assertEqual(self.box.post("tel", "ticket-0001", {PC1: BLOB, PC2: BLOB}), "attente")
        with self.box.cond:
            self.assertEqual(self.box.waiting(PC1, mark=True), ["ticket-0001"])
            self.assertEqual(self.box.waiting(PC1), [])                 # déjà signalé
        self.assertEqual(self.box.lease(PC1, "ticket-0001"), BLOB)
        with self.assertRaises(LookupError):
            self.box.lease(PC2, "ticket-0001")                           # réservé par l'autre PC
        with self.box.cond:
            self.assertEqual(self.box.waiting(PC2), [])
        self.assertEqual(self.box.states(["ticket-0001"]), {"ticket-0001": "recu"})
        self.assertTrue(self.box.filed(PC1, "ticket-0001"))
        self.assertEqual(self.box.states(["ticket-0001"]), {"ticket-0001": "range"})
        self.assertEqual(self.box.tickets, {})                           # paquets effacés
        self.assertEqual(self.box.post("tel", "ticket-0001", {PC1: BLOB}), "range")  # renvoi : rien

    def test_lease_expires_then_other_pc_takes_it(self):
        self.box.post("tel", "ticket-0002", {PC1: BLOB, PC2: BLOB})
        self.box.lease(PC1, "ticket-0002")
        self.clock.t += B.LEASE + 1
        self.assertEqual(self.box.lease(PC2, "ticket-0002"), BLOB)
        self.assertTrue(self.box.filed(PC2, "ticket-0002"))

    def test_refusals(self):
        with self.assertRaises(ValueError):
            self.box.post("tel", "ticket-0003", {PC1: b"\xff\xd8 photo en clair"})
        with self.assertRaises(ValueError):
            self.box.post("tel", "x", {PC1: BLOB})
        with self.assertRaises(PermissionError):
            self.box.post(None, "ticket-0004", {PC1: BLOB})
        for i in range(B.PER_DAY):
            self.box.post("tel", "ticket-1%04d" % i, {PC1: BLOB})
        with self.assertRaises(PermissionError):
            self.box.post("tel", "ticket-9999", {PC1: BLOB})              # limite du jour
        self.box.post("autre", "ticket-8888", {PC1: BLOB})                # autre téléphone : permis
        with self.assertRaises(LookupError):
            self.box.lease(PC2, "ticket-8888")                            # pas de paquet pour ce PC

    def test_unknown_after_restart_then_sent_again(self):
        self.assertEqual(self.box.states(["ticket-0005"]), {"ticket-0005": "inconnu"})
        self.assertEqual(self.box.post("tel", "ticket-0005", {PC1: BLOB}), "attente")


if __name__ == "__main__":
    unittest.main()
