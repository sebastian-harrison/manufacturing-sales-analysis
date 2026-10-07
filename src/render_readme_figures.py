"""Render README figures from existing executed SQL outputs; no pipeline rerun.

Run from any directory with Python 3: python3 src/render_readme_figures.py
Outputs are self-contained SVGs for crisp GitHub rendering.
"""
from pathlib import Path
from decimal import Decimal, ROUND_HALF_UP
import csv
from html import escape
from currency import to_usd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports" / "images"
BLUE = "#466F8F"
LIGHT_BLUE = "#AAC1D1"
ORANGE = "#C67724"
INK = "#243746"
MUTED = "#61717D"
GRID = "#E4EBEF"
PALE = "#F3F6F8"


def rows(path):
    with (ROOT / path).open(newline="") as handle:
        return list(csv.DictReader(handle))


def fmt(number, places=1):
    quantum = Decimal(1).scaleb(-places)
    return f"{Decimal(number).quantize(quantum, rounding=ROUND_HALF_UP):,.{places}f}"


class Figure:
    def __init__(self, width, height, title, description):
        self.parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title description">',
            f'<title id="title">{escape(title)}</title>',
            f'<desc id="description">{escape(description)}</desc>',
            '<rect width="100%" height="100%" fill="#FFFFFF"/>',
        ]

    def text(self, x, y, text, size=18, color=INK, weight="400", anchor="start"):
        self.parts.append(f'<text x="{x}" y="{y}" font-family="Arial, Helvetica, sans-serif" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{escape(str(text))}</text>')

    def rect(self, x, y, w, h, color, radius=0):
        self.parts.append(f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" rx="{radius}" fill="{color}"/>')

    def line(self, x1, y1, x2, y2, color=GRID, width=1):
        self.parts.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}"/>')

    def save(self, name):
        OUT.mkdir(parents=True, exist_ok=True)
        path = OUT / name
        path.write_text("\n".join(self.parts + ["</svg>"]) + "\n")
        print(path.relative_to(ROOT))


def summary():
    annual = rows("reports/company_year.csv")
    concentration = rows("reports/concentration_year.csv")
    assert [r["year"] for r in annual] == ["2011", "2012", "2013", "2014"]
    concentration_by_year = {r["year"]: r for r in concentration}
    annual_by_year = {r["year"]: r for r in annual}
    change_2014 = (Decimal(annual_by_year["2014"]["company_sales"]) / Decimal(annual_by_year["2013"]["company_sales"]) - 1) * 100
    change_full = (Decimal(annual_by_year["2014"]["company_sales"]) / Decimal(annual_by_year["2011"]["company_sales"]) - 1) * 100
    share_change = (Decimal(concentration_by_year["2014"]["top_five_share"]) - Decimal(concentration_by_year["2011"]["top_five_share"])) * 100
    top_five_prior = to_usd(concentration_by_year["2011"]["top_five_sales"]) / Decimal("1000000")
    top_five_current = to_usd(concentration_by_year["2014"]["top_five_sales"]) / Decimal("1000000")
    description = "Annual reported sales in USD millions at fixed 2014 exchange rates, assuming source NGN: " + ", ".join(r["year"] + ": " + fmt(to_usd(r["company_sales"]) / Decimal("1000000"), 2) for r in annual) + ". Annually ranked top-five customer share: " + ", ".join(r["year"] + ": " + fmt(Decimal(concentration_by_year[r["year"]]["top_five_share"]) * 100) + "%" for r in annual) + "."
    f = Figure(1000, 530, "Sales contracted while customer concentration increased", description)
    f.text(32, 38, "Sales contracted while customer concentration increased", 25, weight="700")
    f.text(32, 68, "2011-2014 | Reported sales and customer concentration", 17, MUTED)
    f.line(32, 86, 968, 86)
    f.text(32, 123, "Reported sales", 21, weight="700")
    f.text(32, 149, "USD millions", 17, MUTED)
    f.text(542, 123, "Top-five customer share", 21, weight="700")
    f.text(542, 149, "Annually ranked; full company denominator", 17, MUTED)
    bottom, top, left, right = 405, 184, 86, 456
    for tick in [0, 25, 50, 75]:
        y = bottom - tick / 90 * (bottom - top)
        f.line(left, y, right, y)
        f.text(left - 13, y + 6, str(tick), 17, MUTED, anchor="end")
    for i, r in enumerate(annual):
        amount = to_usd(r["company_sales"]) / Decimal("1000000")
        x = 106 + i * 90
        height = float(amount) / 90 * (bottom - top)
        f.rect(x, bottom - height, 54, height, BLUE if r["year"] == "2014" else LIGHT_BLUE)
        f.text(x + 27, bottom - height - 12, "$" + fmt(amount, 2), 22, weight="700", anchor="middle")
        f.text(x + 27, 435, r["year"], 20, anchor="middle")
    f.text(86, 474, "2014 vs 2013: " + fmt(change_2014) + "%", 19, ORANGE, weight="700")
    f.text(86, 500, "2011 to 2014: " + fmt(change_full) + "%", 18, MUTED)
    left, right = 580, 968
    for tick in [0, 25, 50, 75, 100]:
        y = bottom - tick / 100 * (bottom - top)
        f.line(left, y, right, y)
        f.text(left - 13, y + 6, f"{tick}%", 17, MUTED, anchor="end")
    for i, r in enumerate(annual):
        share = Decimal(concentration_by_year[r["year"]]["top_five_share"]) * 100
        x = 612 + i * 90
        share_height = float(share) / 100 * (bottom - top)
        f.rect(x, top, 54, bottom - top, PALE)
        f.rect(x, bottom - share_height, 54, share_height, BLUE)
        f.text(x + 27, bottom - share_height - 12, fmt(share) + "%", 22, weight="700", anchor="middle")
        f.text(x + 27, 435, r["year"], 20, anchor="middle")
    f.text(580, 474, "Top-five share: +" + fmt(share_change) + " percentage points", 18, BLUE, weight="700")
    f.text(580, 500, "Top-five sales: $" + fmt(top_five_prior, 2) + " to $" + fmt(top_five_current, 2) + " million", 18, MUTED)
    f.save("readme-sales-concentration.svg")


def priorities():
    accounts = sorted([r for r in rows("reports/account_review_priorities.csv") if r["year"] == "2014"], key=lambda r: int(r["priority_review_rank"]))[:4]
    names = {"CIQ0001": "Queensway", "CIP0001": "P.G.N", "CIA0013": "Asaba", "CIB0004": "Borno"}
    specs = {r["contributor_key"]: r for r in rows("reports/revenue_driver_details.csv") if r["current_year"] == "2014" and r["contributor_type"] == "thickness"}
    annual = {r["year"]: Decimal(r["company_sales"]) for r in rows("reports/company_year.csv")}
    net_loss = annual["2013"] - annual["2014"]
    account_share = -sum(Decimal(r["sales_change"]) for r in accounts) / net_loss * 100
    spec_share = -sum(Decimal(specs[code]["sales_change"]) for code in ["0.55", "0.45", "0.42"]) / net_loss * 100
    intersection = next(r for r in rows("reports/customer_thickness_changes.csv") if r["current_year"] == "2014" and r["customer_code"] == "CIP0001" and r["thickness_code"] == "0.42")
    intersection_loss = to_usd(-Decimal(intersection["sales_change"])) / Decimal("1000000")
    description = "Account losses in USD millions at fixed 2014 exchange rates: " + ", ".join(names[r["customer_code"]] + ": " + fmt(to_usd(-Decimal(r["sales_change"])) / Decimal("1000000"), 2) for r in accounts) + ". Source thickness losses: " + ", ".join(code + ": " + fmt(to_usd(-Decimal(specs[code]["sales_change"])) / Decimal("1000000"), 2) for code in ["0.55", "0.45", "0.42"]) + "."
    f = Figure(1000, 376, "2014 sales-loss review priorities", description)
    f.text(32, 38, "2014 sales-loss review priorities", 25, weight="700")
    f.text(32, 68, "2014 vs 2013 | Loss magnitudes in $ millions", 17, MUTED)
    f.line(32, 86, 968, 86)
    f.text(32, 120, "Four accounts: " + fmt(account_share) + "% of net decline", 21, weight="700")
    f.text(542, 120, "Thickness losses: " + fmt(spec_share) + "% of net decline", 21, weight="700")
    f.text(32, 149, "Company net loss: $" + fmt(to_usd(net_loss) / Decimal("1000000"), 2) + " million", 17, MUTED)
    f.text(542, 149, "Other specifications provide offsets", 17, MUTED)
    for i, r in enumerate(accounts):
        value = to_usd(-Decimal(r["sales_change"])) / Decimal("1000000")
        y = 183 + i * 44
        f.text(32, y + 23, names[r["customer_code"]], 21)
        width = float(value) / 5 * 290
        f.rect(154, y + 5, width, 26, ORANGE, 2)
        f.text(154 + width + 11, y + 25, "$" + fmt(value, 2), 22, weight="700")
    for i, code in enumerate(["0.55", "0.45", "0.42"]):
        value = to_usd(-Decimal(specs[code]["sales_change"])) / Decimal("1000000")
        y = 183 + i * 44
        f.text(542, y + 23, code, 21)
        width = float(value) / 5 * 290
        f.rect(616, y + 5, width, 26, ORANGE, 2)
        f.text(616 + width + 11, y + 25, "$" + fmt(value, 2), 22, weight="700")
    f.text(542, 349, "P.G.N: $" + fmt(intersection_loss, 2) + " million of the 0.42 loss", 18, BLUE, weight="700")
    f.save("readme-review-priorities.svg")


if __name__ == "__main__":
    summary()
    priorities()
