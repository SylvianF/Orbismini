"""PC connus d'Orbiscan par Orbismini : chaque PC est retenu pour de bon à sa première venue.

Pour chaque PC (identifiant du relais), Orbismini garde l'empreinte de son secret et celle de sa clé
publique, rien d'autre (ni le secret, ni la clé privée, qui ne quitte jamais le PC). Ensuite, toute
venue avec un autre secret ou une autre clé est refusée : personne ne peut se faire passer pour un PC
déjà connu, même après un redémarrage de Render.

Où : fichier pc.json de la branche « orbiscan-pc » du dépôt d'Orbismini (Render ne déploie que main :
pas de redémarrage quand un PC est ajouté). Accès par une clé GitHub limitée à ce dépôt, rangée dans
les réglages de Render (ORBISCAN_GITHUB_TOKEN). Sans cette clé, ou si GitHub ne répond pas, aucun
nouveau PC n'est accepté (on refuse plutôt que d'oublier).

Remise à zéro d'un PC (Windows réinstallé, nouveau PC) : à la main seulement, par Sylvian, avec le
code ORBISCAN_ADMIN (page /orbiscan-pc d'Orbismini)."""

import base64
import hashlib
import hmac
import json
import os
import threading
import time
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.request import Request, urlopen

REPO = os.environ.get("ORBISCAN_GITHUB_REPO", "Tawek8/mon-cours-or")
BRANCH = "orbiscan-pc"
FILE = "pc.json"
API = "https://api.github.com"


def digest(text):
    return hashlib.sha256(str(text).encode("utf-8")).hexdigest()


def key_print(key):
    """Empreinte de la clé publique du PC (n et e)."""
    return digest((key or {}).get("n", "") + "." + (key or {}).get("e", ""))


def http(method, url, token, body=None):
    """Appel à GitHub : (statut, réponse JSON). Remplacé dans les tests."""
    data = json.dumps(body).encode() if body is not None else None
    req = Request(url, data, method=method, headers={
        "Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
        "User-Agent": "orbismini", "Content-Type": "application/json"})
    try:
        with urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read() or b"{}")
    except HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


# ---------------------------------------------------------------- fichier JSON sur une branche
# Commun à pc.json (branche « orbiscan-pc ») et à alertes.json (branche « alertes »,
# alerte_appareils.py) : Render ne déploie que main, rien ne redémarre quand ils changent.
def _url(path):
    return f"{API}/repos/{REPO}/{path}"


def read_file(token, branch, file):
    """(statut, contenu, version) : contenu {} et version None si le fichier n'existe pas encore
    (404) ; contenu None pour toute autre réponse de GitHub."""
    status, out = http("GET", _url(f"contents/{file}?ref={branch}"), token)
    if status == 200:
        return status, json.loads(base64.b64decode(out["content"])), out["sha"]
    if status == 404:
        return status, {}, None
    return status, None, None


def ensure_branch(token, branch):
    """Crée la branche à partir de main si elle n'existe pas encore."""
    status, _ = http("GET", _url(f"git/ref/heads/{branch}"), token)
    if status == 200:
        return
    status, main = http("GET", _url("git/ref/heads/main"), token)
    if status != 200:
        raise PermissionError("dépôt inaccessible (GitHub %s)" % status)
    status, _ = http("POST", _url("git/refs"), token, {"ref": "refs/heads/" + branch, "sha": main["object"]["sha"]})
    if status not in (201, 422):     # 422 : créée entre-temps
        raise PermissionError("branche impossible à créer (GitHub %s)" % status)


def write_file(token, branch, file, sha, text, message):
    """Écrit le texte (JSON) sur la branche, créée à la première écriture : (statut, nouvelle
    version) ; version None si GitHub refuse (conflit, panne…)."""
    if sha is None:
        ensure_branch(token, branch)
    body = {"message": message, "branch": branch, "content": base64.b64encode(text.encode()).decode()}
    if sha:
        body["sha"] = sha
    status, out = http("PUT", _url(f"contents/{file}"), token, body)
    return status, (out["content"]["sha"] if status in (200, 201) else None)


class Store:
    def __init__(self, token=None, admin=None):
        self.token = os.environ.get("ORBISCAN_GITHUB_TOKEN", "").strip() if token is None else token
        self.admin = os.environ.get("ORBISCAN_ADMIN", "").strip() if admin is None else admin
        self.lock = threading.Lock()
        self.pcs = None      # {pc: {name, secret, key, first}} une fois lu sur GitHub
        self.sha = None      # version du fichier sur GitHub

    # ---------------------------------------------------------------- GitHub
    def _load(self):
        if self.pcs is not None:
            return
        if not self.token:
            raise PermissionError("Orbismini ne peut pas retenir les PC (ORBISCAN_GITHUB_TOKEN absent)")
        status, pcs, sha = read_file(self.token, BRANCH, FILE)
        if pcs is None:
            raise PermissionError("liste des PC illisible pour l'instant (GitHub %s)" % status)
        self.pcs, self.sha = pcs, sha

    def _save(self, pcs, message):
        status, sha = write_file(self.token, BRANCH, FILE, self.sha, json.dumps(pcs, indent=2, sort_keys=True), message)
        if sha is None:
            self.pcs = None              # relire au prochain passage (conflit, panne…)
            raise PermissionError("PC non enregistré (GitHub %s)" % status)
        self.sha, self.pcs = sha, pcs

    # ---------------------------------------------------------------- relais
    def check(self, pc, name, secret, key):
        """Laisse passer un PC connu avec son secret et sa clé d'origine ; retient un PC nouveau ;
        refuse tout le reste (PermissionError)."""
        s, k = digest(secret), key_print(key)
        with self.lock:
            self._load()
            known = self.pcs.get(pc)
            if known:
                if not (hmac.compare_digest(known["secret"], s) and hmac.compare_digest(known["key"], k)):
                    raise PermissionError("PC déjà connu avec un autre secret ou une autre clé")
                return False
            pcs = dict(self.pcs)
            pcs[pc] = dict(name=str(name or pc)[:40], secret=s, key=k,
                           first=datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M"))
            self._save(pcs, "Orbiscan : nouveau PC « %s »" % pcs[pc]["name"])
            return True

    # ---------------------------------------------------------------- Sylvian
    def admin_ok(self, code):
        ok = bool(self.admin) and hmac.compare_digest(str(code or "").encode(), self.admin.encode())
        if not ok:
            time.sleep(1)                # freine les essais
        return ok

    def listing(self, code):
        if not self.admin_ok(code):
            raise PermissionError("code incorrect")
        with self.lock:
            self._load()
            return [dict(pc=p, name=x["name"], first=x["first"], key=x["key"][:12]) for p, x in sorted(self.pcs.items())]

    def reset(self, code, pc):
        if not self.admin_ok(code):
            raise PermissionError("code incorrect")
        with self.lock:
            self._load()
            if pc not in self.pcs:
                return False
            pcs = dict(self.pcs)
            name = pcs.pop(pc)["name"]
            self._save(pcs, "Orbiscan : PC « %s » remis à zéro" % name)
            return True


STORE = Store()

ADMIN_PAGE = """<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PC d'Orbiscan</title>
<style>
  body { margin: 0; background: #121d25; color: #edf2f5; font: 16px/1.45 -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 520px; margin: 0 auto; padding: 20px 16px; }
  h1 { color: #e9bf75; font-size: 21px; margin: 0 0 6px; }
  p { color: #b5c7d3; font-size: 14px; }
  input, button { font: inherit; border-radius: 10px; border: 1px solid #344853; padding: 10px 12px; }
  input { width: 100%; box-sizing: border-box; background: #1b2a34; color: #edf2f5; margin: 8px 0; }
  button { background: #e9bf75; color: #18242b; font-weight: 600; border: 0; }
  .pc { background: #1b2a34; border: 1px solid #344853; border-radius: 12px; padding: 12px; margin: 10px 0; }
  .pc small { display: block; color: #b5c7d3; }
  .pc button { margin-top: 8px; background: transparent; color: #ff9ca4; border: 1px solid #ff9ca4; }
  .err { color: #ff9ca4; }
</style></head>
<body><main>
<h1>PC d'Orbiscan</h1>
<p>Chaque PC est retenu à sa première venue, avec sa clé. Remets un PC à zéro seulement s'il a été
réinstallé ou remplacé : il sera retenu de nouveau à sa prochaine venue.</p>
<form id="f"><input id="code" type="password" placeholder="Code (ORBISCAN_ADMIN)" autocomplete="off">
<button>Afficher les PC</button></form>
<p class="err" id="err"></p><div id="list"></div>
<script>
const $ = s => document.querySelector(s);
async function call(body) {
  const r = await fetch('/api/orbiscan/pc-admin', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(Object.assign({ code: $('#code').value }, body)) });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw Error(d.error || 'erreur ' + r.status);
  return d;
}
async function show() {
  $('#err').textContent = '';
  try {
    const d = await call({});
    $('#list').replaceChildren(...(d.pcs.length ? d.pcs.map(p => {
      const div = document.createElement('div'); div.className = 'pc';
      div.innerHTML = '<b></b><small></small><button type="button">Remettre à zéro</button>';
      div.querySelector('b').textContent = p.name;
      div.querySelector('small').textContent = 'Retenu le ' + p.first + ' · clé ' + p.key + '… · ' + p.pc;
      div.querySelector('button').onclick = async () => {
        if (!confirm('Remettre « ' + p.name + ' » à zéro ?')) return;
        try { await call({ reset: p.pc }); show(); } catch (e) { $('#err').textContent = e.message; }
      };
      return div;
    }) : [Object.assign(document.createElement('p'), { textContent: 'Aucun PC retenu pour l’instant.' })]));
  } catch (e) { $('#err').textContent = e.message; }
}
$('#f').onsubmit = e => { e.preventDefault(); show(); };
</script></main></body></html>
"""
