"""Tickets de carburant : boîte aux lettres d'Orbismini entre le téléphone et les PC.

Le téléphone (ticket.js) envoie un ticket depuis n'importe où (réseau mobile compris) : la photo,
l'agence, le montant et le jour, scellés sur le téléphone pour CHAQUE PC jumelé (clé publique du PC,
RSA-OAEP 2048 + AES-256-GCM) et signés avec le secret du téléphone que seul ce PC connaît. Orbismini
ne garde que ces paquets illisibles, en mémoire vive, jamais sur disque.

Le relais d'un PC est prévenu par sa ligne déjà ouverte (orbiscan_tunnel.Tunnel.relay_wait) ; il
réserve le ticket (10 minutes), le déchiffre, vérifie la signature et le passe à Orbis. Quand Orbis
l'a rangé, le relais le dit : le ticket est effacé ici (tous ses paquets). Sans « rangé » dans les
10 minutes, il redevient disponible pour l'autre PC.

Render perd sa mémoire à chaque redémarrage : le téléphone garde son ticket scellé jusqu'à
« rangé » et le renvoie tout seul s'il n'est plus connu ici. L'identifiant est tiré par le
téléphone et ne change jamais : Orbis ne range jamais deux fois le même ticket.
"""

import re
import time

TICKET_ID = re.compile(r"[A-Za-z0-9-]{8,64}")
PC_ID = re.compile(r"[\w-]{8,40}")
MAGIC = b"OSC1"
LEASE = 600                 # secondes : réservation par un relais
ANNOUNCE_AGAIN = 60         # secondes : un ticket pas encore réservé est redonné au relais
KEEP = 7 * 86400            # ticket jamais relevé : oublié au bout de 7 jours
KEEP_DONE = 30 * 86400      # « rangé » gardé 30 jours pour l'état du téléphone
MAX_PACKET = 12 * 1024 * 1024
MAX_TOTAL = 120 * 1024 * 1024
MAX_TICKETS = 300
MAX_PCS_PER_TICKET = 4
PER_DAY = 100               # dépôts par téléphone et par jour (tickets, propositions, virements faits)


BOX = re.compile(r"[0-9a-f]{64}")
MAX_FIGURES = 300 * 1024
MAX_BOXES = 300


class Figures:
    """Chiffres d'Orbis pour les téléphones (réglés dans Orbis, Réglages › Téléphones) : le relais
    les chiffre avec une clé tirée du secret du téléphone et les dépose dans sa boîte ; Orbismini
    garde le dernier paquet de chaque boîte, en mémoire, sans pouvoir le lire ni savoir à qui il est."""

    def __init__(self, clock=time.time):
        self.clock = clock
        self.boxes = {}      # boîte → (paquet, moment du dépôt)

    def put(self, box, blob):
        if not BOX.fullmatch(str(box or "")) or not isinstance(blob, bytes) or not blob.startswith(b"OSC2"):
            raise ValueError("chiffres invalides")
        if len(blob) > MAX_FIGURES:
            raise ValueError("chiffres trop lourds")
        self.boxes[box] = (blob, self.clock())
        while len(self.boxes) > MAX_BOXES:
            del self.boxes[min(self.boxes, key=lambda b: self.boxes[b][1])]

    def get(self, boxes):
        return {b: self.boxes[b][0] for b in boxes if b in self.boxes}


class Mailbox:
    def __init__(self, cond, clock=time.time):
        self.cond = cond     # verrou partagé avec la ligne ouverte des relais (Tunnel.lock)
        self.clock = clock
        self.tickets = {}    # id → {packets: {pc: bytes}, device, at, lease: {pc, until} | None, told: {pc: t}}
        self.done = {}       # id → moment du rangement
        self.counts = {}     # (téléphone, jour) → nombre de tickets

    # ---------------------------------------------------------------- ménage
    def _purge(self):
        now = self.clock()
        for i in [i for i, t in self.tickets.items() if now - t["at"] > KEEP]:
            del self.tickets[i]
        for i in [i for i, t in self.done.items() if now - t > KEEP_DONE]:
            del self.done[i]
        today = time.strftime("%Y-%m-%d", time.gmtime(now))
        for k in [k for k in self.counts if k[1] != today]:
            del self.counts[k]
        for t in self.tickets.values():
            if t["lease"] and t["lease"]["until"] < now:
                t["lease"] = None

    def _held(self):
        return sum(len(p) for t in self.tickets.values() for p in t["packets"].values())

    # ---------------------------------------------------------------- téléphone
    def post(self, device, tid, packets):
        """Dépôt (ou nouvel envoi) d'un ticket : renvoie son état."""
        if not device:
            raise PermissionError("Téléphone non reconnu, recharge la page.")
        if not TICKET_ID.fullmatch(str(tid or "")):
            raise ValueError("ticket invalide")
        if not isinstance(packets, dict) or not 0 < len(packets) <= MAX_PCS_PER_TICKET:
            raise ValueError("ticket sans PC")
        for pc, blob in packets.items():
            if not PC_ID.fullmatch(str(pc)) or not isinstance(blob, bytes) or not blob.startswith(MAGIC):
                raise ValueError("ticket non chiffré refusé")
            if len(blob) > MAX_PACKET:
                raise ValueError("photo trop lourde")
        with self.cond:
            self._purge()
            if tid in self.done:
                return "range"
            if tid in self.tickets:
                return self._state(tid)
            now = self.clock()
            day = (device, time.strftime("%Y-%m-%d", time.gmtime(now)))
            if self.counts.get(day, 0) >= PER_DAY:
                raise PermissionError("Trop de tickets aujourd'hui depuis ce téléphone.")
            if len(self.tickets) >= MAX_TICKETS or self._held() + sum(map(len, packets.values())) > MAX_TOTAL:
                raise PermissionError("Boîte pleine pour l'instant, réessaie plus tard.")
            self.counts[day] = self.counts.get(day, 0) + 1
            self.tickets[tid] = dict(packets=dict(packets), device=device, at=now, lease=None, told={})
            self.cond.notify_all()           # réveille la ligne ouverte des relais
            return "attente"

    def _state(self, tid):
        if tid in self.done:
            return "range"
        t = self.tickets.get(tid)
        if not t:
            return "inconnu"
        return "recu" if t["lease"] else "attente"

    def states(self, ids):
        with self.cond:
            self._purge()
            return {i: self._state(i) for i in ids if TICKET_ID.fullmatch(str(i))}

    # ---------------------------------------------------------------- relais
    def waiting(self, pc, mark=False):
        """Tickets à signaler à ce relais : non réservés, avec un paquet pour lui, pas signalés
        depuis une minute. mark : on les signale maintenant."""
        now = self.clock()
        self._purge()
        out = [i for i, t in self.tickets.items()
               if pc in t["packets"] and not t["lease"] and now - t["told"].get(pc, 0) > ANNOUNCE_AGAIN]
        if mark:
            for i in out:
                self.tickets[i]["told"][pc] = now
        return out

    def lease(self, pc, tid):
        """Réservation (10 minutes) : le paquet scellé pour ce PC."""
        with self.cond:
            self._purge()
            t = self.tickets.get(str(tid))
            if not t or pc not in t["packets"]:
                raise LookupError("ticket inconnu")
            if t["lease"] and t["lease"]["pc"] != pc:
                raise LookupError("ticket pris par un autre PC")
            t["lease"] = dict(pc=pc, until=self.clock() + LEASE)
            return t["packets"][pc]

    def filed(self, pc, tid):
        """Orbis a rangé le ticket : tout est effacé ici."""
        with self.cond:
            self._purge()
            tid = str(tid)
            t = self.tickets.get(tid)
            if t is None:
                if tid in self.done:
                    return True
                raise LookupError("ticket inconnu")
            if pc not in t["packets"]:
                raise LookupError("ticket inconnu")
            del self.tickets[tid]
            self.done[tid] = self.clock()
            return True
