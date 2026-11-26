"""Proposition de rachat (PDF A4), seule dépendance : ReportLab et ses polices Vera.

Fabriquée à l'identique par Orbis (pdf_document.make_purchase_pdf, fiche client du poste)
et par Orbismini, qui en garde une copie (« Envoyer au client » de l'application iPhone,
demande de Sylvian du 26/11/2026). À chaque changement de ce fichier, prévenir la session
Orbismini pour qu'elle recopie le fichier tel quel.

make(rows, client, agency, contact, now=None, internal=False, logo=None) -> octets du PDF
- rows : lignes de l'estimation (window.GoldEstimate.snapshot() d'estimation.js : name,
  quantity, count, mode, titre, reference, resole, productId, lingot, percent, result {gross,
  tax, net, taxLabel, taxRate, taxBase}) ;
- client : {name, address, postalCode, city, phone, email} (seul le nom est obligatoire) ;
- agency : {company, address, phone, email}, mentions de l'agence ;
- contact : « Votre contact : … » ;
- internal : True ajoute les lignes de commission (impression interne d'Orbis, jamais pour
  le client) ;
- logo : chemin du logo (logo-impression.jpg à côté de ce fichier par défaut).
Polices : Bitstream Vera, livrées avec ReportLab (licence libre, redistribuable).
"""

import sys
from datetime import datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from io import BytesIO
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if (_HERE / "vendor" / "reportlab").is_dir():
    sys.path.insert(0, str(_HERE / "vendor"))  # Orbis : ReportLab livré avec le programme
import reportlab
from reportlab.lib.colors import HexColor, black, white
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase.pdfmetrics import registerFont, stringWidth
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas

_FONT_DIR = Path(reportlab.__file__).parent / "fonts"
registerFont(TTFont("GoldRegular", str(_FONT_DIR / "Vera.ttf")))
registerFont(TTFont("GoldBold", str(_FONT_DIR / "VeraBd.ttf")))
LOGO = _HERE / "logo-impression.jpg"


def euro(n):
    """1 234,50 € (arrondi au centime le plus proche, comme Orbis)."""
    n = Decimal(n).quantize(Decimal(".01"), rounding=ROUND_HALF_UP)
    return format(n, ",.2f").replace(",", " ").replace(".", ",") + " €"


def wrap(text, width, size, font="GoldRegular"):
    lines = []
    for paragraph in str(text or "").splitlines() or [""]:
        line = ""
        for word in paragraph.split():
            if line and stringWidth(line + " " + word, font, size) > width:
                lines.append(line)
                line = ""
            for char in word:
                if stringWidth(line + char, font, size) > width:
                    lines.append(line)
                    line = ""
                line += char
            line += " "
        lines.append(line.strip())
    return lines


class Feuille:
    """Aides de dessin communes aux documents A4 : texte, paragraphe, filet, en-tête."""

    def __init__(self, page, size=9, leading=1.22, logo=None):
        self.page, self.size, self.leading = page, size, leading
        self.logo = logo or LOGO
        self.width, self.height = A4
        self.left = 20 * mm
        self.right = self.width - self.left

    def label(self, x, y, text, size=None, font="GoldRegular", color=black, align="left"):
        page = self.page
        page.setFont(font, size or self.size)
        page.setFillColor(color)
        {"left": page.drawString, "right": page.drawRightString, "center": page.drawCentredString}[align](x, y, str(text))

    def block(self, x, y, text, w, size=None, font="GoldRegular", color=black, leading=None):
        size = size or self.size
        for line in wrap(text, w, size, font):
            self.label(x, y, line, size, font, color)
            y -= leading or size * self.leading
        return y

    def rule(self, y, x=None, end=None, color=HexColor("#d5d5d5")):
        self.page.setLineWidth(0.5)
        self.page.setStrokeColor(color)
        self.page.line(self.left if x is None else x, y, self.right if end is None else end, y)

    def header(self, agency, collaborator, title, client, now):
        """Logo, coordonnées de l'agence, titre, date et bloc client ; renvoie le haut du tableau."""
        left, right, width, height = self.left, self.right, self.width, self.height
        available = right - left
        logo_width = min(315, available * 0.66)
        self.page.drawImage(
            str(self.logo),
            left,
            height - left - 28,
            width=logo_width,
            height=logo_width * 60 / 656,
        )
        lines = wrap(
            "\n".join(
                [agency["company"], agency["address"], agency["phone"], agency["email"], "Votre contact : " + collaborator]
            ),
            available - logo_width - 12,
            8,
        )
        for i, line in enumerate(lines):
            self.label(right, height - left - 5 - i * 9, line, 8, align="right")
        heading_y = height - left - max(63, len(lines) * 9 + 19)
        self.label(width / 2, heading_y, title, 18, align="center")
        self.label(width / 2, heading_y - 16, "Ne constitue pas une facture", 8, color=HexColor("#777777"), align="center")
        client_y = heading_y - 52
        client_x = left + available * 0.53
        self.label(left, client_y, "Date : " + now.strftime("%d/%m/%Y à %H:%M"), 9)
        self.label(client_x, client_y, "CLIENT", 10, "GoldBold", HexColor("#9c7a35"))
        text = "\n".join(
            v
            for v in [
                client["name"],
                client.get("address", ""),
                (client.get("postalCode", "") + " " + client.get("city", "")).strip(),
                client.get("phone", ""),
                client.get("email", ""),
            ]
            if v
        )
        bottom = self.block(client_x, client_y - 17, text, right - client_x, 10.5)
        return min(client_y - 88, bottom - 22)


def make(rows, client, agency, contact, now=None, internal=False, logo=None):
    """Octets du PDF « Proposition de rachat » ; ValueError si une ligne est incohérente."""

    def amount(value):
        try:
            n = Decimal(str(value))
            if not n.is_finite() or abs(n) > Decimal("1e12"):
                raise ValueError()
            return n
        except (InvalidOperation, ValueError, TypeError):
            raise ValueError("Montant de proposition invalide.")

    def percent_text(rate):
        return format(rate * 100, ".2f").replace(".", ",")

    internal = internal is True
    if not isinstance(rows, list) or not rows or len(rows) > 100:
        raise ValueError("Complétez les lignes de la proposition avant impression.")
    # Lingots (1 kg et plus, pas les lingotins ; choix de Sylvian, 22/11/2026) : 25 % du
    # net versé le jour même, le solde 10 jours plus tard ; le reste est réglé ce jour.
    def is_lingot(row):
        # « lingot » envoyé par l'écran (estimation.js) ; ligne sans lui : le lingot 1 kg.
        return row.get("lingot", row.get("productId") == "cpor") is True

    split_lingot = any(isinstance(row, dict) and is_lingot(row) for row in rows)
    lingot_net = Decimal(0)
    groups = {}
    totals = {key: Decimal(0) for key in ["gross", "tax", "net"]}
    prepared = []
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("result"), dict):
            raise ValueError("Une ligne est incomplète.")
        result = row["result"]
        values = {key: amount(result.get(key)) for key in totals}
        count = amount(row.get("count"))
        if (
            count <= 0
            or min(values.values()) < 0
            or abs(values["gross"] - values["tax"] - values["net"]) > Decimal(".001")
        ):
            raise ValueError("Les montants de la proposition sont incohérents.")
        title = str(row.get("name", "")).strip()
        mode = str(row.get("mode", ""))
        if mode == "Boursable":
            # « Cours de la pièce / du lingotin / du lingot » : pas de cours CPoR pour
            # toutes les pièces (5 F Semeuse…), le libellé suit l'objet.
            lowered = title.lower()
            label = (
                "Cours du lingotin"
                if "lingotin" in lowered
                else "Cours du lingot"
                if "lingot" in lowered or row.get("productId") == "cpor"
                else "Cours de la pièce"
            )
            quote = amount(row.get("reference") or 0)
            mode = (
                label + " : " + euro(quote)
                if quote > 0
                else label + " : indisponible"
            )
        resole = amount(row.get("resole") or 0)
        if resole < 0:
            raise ValueError("Ressemelage invalide.")
        details = " · ".join(
            str(value)
            for value in [
                row.get("titre", ""),
                mode,
                "Ressemelage du certificat : −" + euro(resole) if resole else "",
            ]
            if value
        )
        if not title or len(title + details) > 2000:
            raise ValueError("La désignation du produit est invalide.")
        tax_label = str(result.get("taxLabel", ""))
        rate = amount(result.get("taxRate"))
        base = amount(result.get("taxBase"))
        if len(tax_label) > 60 or not 0 <= rate <= 1 or base < 0:
            raise ValueError("Détail de taxe invalide.")
        key = (tax_label, rate)
        group = groups.setdefault(key, dict(base=Decimal(0), tax=Decimal(0)))
        group["base"] += base
        group["tax"] += values["tax"]
        for key in totals:
            totals[key] += values[key]
        if is_lingot(row):
            lingot_net += values["net"]
        before = values["gross"]
        unit = values["gross"] / count
        if internal:
            unit = amount(row.get("reference"))
            if unit <= 0:
                raise ValueError(
                    "Référence du produit manquante pour détailler la commission."
                )
            before = (unit * count).quantize(Decimal(".01"), rounding="ROUND_HALF_UP")
        prepared.append(
            dict(
                name=title,
                details=details,
                percent="",
                quantity=str(row.get("quantity", "")),
                unit=euro(unit),
                gross=euro(before),
                tax=tax_label
                + (" " + percent_text(rate) + " %" if rate else "")
                + "\n"
                + ("-" if values["tax"] else "")
                + euro(values["tax"]),
                net=euro(values["net"]),
            )
        )
        if internal:
            commission = before - values["gross"]
            percentage = (
                amount(row.get("percent"))
                if row.get("percent") is not None
                else commission / before * 100
            )
            prepared.append(
                dict(
                    name="Commission "
                    + format(percentage, ".2f").replace(".", ",")
                    + " %",
                    details="",
                    percent="",
                    quantity="",
                    unit=euro(-commission / count),
                    gross=euro(-commission),
                    tax="",
                    net="",
                    commission=True,
                )
            )
    client = dict(client or {})
    if not str(client.get("name") or "").strip():
        raise ValueError("Renseignez le nom du client avant impression.")
    if sum(len(str(v)) for v in client.values()) > 6000:
        raise ValueError("Les coordonnées client sont trop longues.")
    output = BytesIO()
    page = Canvas(output, pagesize=A4, pageCompression=1)
    page.setTitle("Proposition de rachat")
    page.setAuthor("Orbis")
    width = A4[0]
    left = 20 * mm
    right = width - left
    available = right - left
    now = now or datetime.now()
    gold = HexColor("#9c7a35")
    pale = HexColor("#f1ebdd")
    dark = HexColor("#292923")
    sheet = Feuille(page, logo=logo)
    label, block, rule = sheet.label, sheet.block, sheet.rule
    table_top = sheet.header(agency, contact, "Proposition de rachat", client, now)
    columns = [available * x for x in [0.30, 0.12, 0.14, 0.14, 0.16, 0.14]]
    positions = [left]
    for w in columns:
        positions.append(positions[-1] + w)
    count = len(rows)
    footer_top = 115
    layout = None
    for size in [9, 8.5, 8, 7.5]:
        drawn = []
        for row in prepared:
            name_lines = wrap(row["name"], columns[0] - 10, size, "GoldBold")
            details = (
                [" · ".join(v for v in [row["details"], row["percent"]] if v)]
                if count > 4
                else [row["details"], row["percent"]]
            )
            for detail in details:
                if detail:
                    name_lines += wrap(detail, columns[0] - 10, size - 1)
            cells = [name_lines] + [
                wrap(row[key], w - 10, size)
                for key, w in zip(
                    ["quantity", "unit", "gross", "tax", "net"], columns[1:]
                )
            ]
            minimum = (
                19
                if row.get("commission")
                else 48 if count <= 2 else 36 if count <= 4 else size + 7
            )
            h = max(minimum, max(map(len, cells)) * (size + 2) + 6)
            drawn.append((cells, h))
        table_bottom = table_top - 25 - sum(h for _, h in drawn)
        recap_height = max(105 if split_lingot else 62, 23 + len(groups) * 14)
        summary_top = min(table_bottom - 24, 405) if count <= 4 else table_bottom - 16
        if summary_top - recap_height > footer_top + 15:
            layout = (size, drawn, summary_top)
            break
    if layout is None:
        raise ValueError(
            "La proposition est trop volumineuse pour rester lisible sur une page. Réduisez les descriptions ou répartissez les lignes."
        )
    size, drawn, summary_top = layout
    page.setFillColor(pale)
    page.rect(left, table_top - 25, available, 25, fill=1, stroke=0)
    for i, title in enumerate(
        ["Produit", "Qté / Poids", "P.U HT", "HT", "Taxe", "TTC"]
    ):
        label(
            positions[i] + 5 if i == 0 else positions[i + 1] - 5,
            table_top - 16,
            title,
            7.5,
            align="left" if i == 0 else "right",
        )
    y = table_top - 25
    for cells, h in drawn:
        for i, lines in enumerate(cells):
            baseline = y - ((h - len(lines) * (size + 2)) / 2) - size
            for j, line in enumerate(lines):
                label(
                    positions[i] + 5 if i == 0 else positions[i + 1] - 5,
                    baseline,
                    line,
                    size if i or j == 0 else size - 1,
                    "GoldBold" if i == 0 and j == 0 else "GoldRegular",
                    align="left" if i == 0 else "right",
                )
                baseline -= size + 2
        y -= h
        rule(y)
    tax_width = available * 0.47
    summary_left = left + available * 0.53
    label(left, summary_top, "Récapitulatif des taxes", 9, "GoldBold")
    ty = summary_top - 18
    page.setFillColor(pale)
    page.rect(left, ty - 5, tax_width, 17, fill=1, stroke=0)
    offsets = [0, 0.30, 0.47, 0.73, 1]
    for i, title in enumerate(["Taxe", "Taux", "Base", "Montant"]):
        label(
            left + 4 if i == 0 else left + tax_width * offsets[i + 1] - 4,
            ty,
            title,
            7,
            align="left" if i == 0 else "right",
        )
    for (title, rate), group in groups.items():
        ty -= 14
        label(left + 4, ty, title, 7)
        for value, pos in [
            (percent_text(rate) + " %", 0.47),
            (euro(group["base"]), 0.73),
            (("-" if group["tax"] else "") + euro(group["tax"]), 1),
        ]:
            label(left + tax_width * pos - 4, ty, value, 6.8, align="right")
        rule(ty - 5, left, left + tax_width)
    summary_values = [
        ("Total avant taxes", totals["gross"]),
        ("Total des taxes", -totals["tax"]),
        ("Net à verser au client", totals["net"]),
    ]
    if split_lingot:
        balance = lingot_net - (lingot_net * Decimal(".25")).quantize(
            Decimal(".01"), rounding="ROUND_HALF_UP"
        )
        summary_values.extend(
            [
                (
                    "Versé ce jour 25 %"
                    if lingot_net == totals["net"]
                    else "Versé ce jour (25 % des lingots)",
                    totals["net"] - balance,
                ),
                (
                    "Solde versé le " + (now + timedelta(days=10)).strftime("%d/%m/%Y"),
                    balance,
                ),
            ]
        )
    for i, (title, value) in enumerate(summary_values):
        y = summary_top - i * 21
        if i == 2:
            page.setFillColor(dark)
            page.rect(summary_left, y - 6, right - summary_left, 22, fill=1, stroke=0)
        label(
            summary_left + 5,
            y,
            title,
            8.5 if i == 2 else 9,
            font="GoldBold" if i == 2 else "GoldRegular",
            color=white if i == 2 else black,
        )
        label(
            right - 5,
            y,
            euro(value),
            9,
            color=white if i == 2 else black,
            align="right",
        )
        if i != 2:
            rule(y - 6, summary_left, right)
    rule(footer_top, color=gold)
    block(
        left,
        footer_top - 15,
        "Les cours de l’or et de l’argent évoluant, cette proposition est valable pendant 2 heures à compter de son établissement.",
        available,
        8,
    )
    label(
        left,
        footer_top - 44,
        "Valable jusqu’au "
        + (now + timedelta(hours=2)).strftime("%d/%m/%Y à %H:%M")
        + ".",
        8,
        "GoldBold",
    )
    page.showPage()
    page.save()
    return output.getvalue()
