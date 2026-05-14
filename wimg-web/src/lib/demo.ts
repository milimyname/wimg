import {
  importCsv,
  autoCategorize,
  detectRecurring,
  takeSnapshot,
  opfsSave,
  type ImportResult,
} from "$lib/wasm";
import { LS_DEMO_LOADED } from "$lib/config";

// Demo data is intentionally rich so every card has something to show:
// - 8 months of history → spending heatmap, net-worth chart, recurring detection
// - 9 stable recurring subs at different intervals → recurring detection
// - Intro-priced sub (€4.99 × 2 → €12.99 × 6) → exercises new bimodal-price
//   detection in recurring.zig
// - Stale sub that stopped 5 months ago → exercises new inactive flag
// - Seasonal noise (Christmas spike, summer travel) → realistic donut + delta

const MONTHS_OF_HISTORY = 8;

// --- Stable monthly fixed costs ---
// Drawn on a fixed day each month, exact amount, easy for recurring detection.
const STABLE_MONTHLY: { desc: string; day: number; amount: number }[] = [
  { desc: "GEHALT {MONTH} {YEAR} ARBEITGEBER GMBH", day: 1, amount: 325000 },
  { desc: "MIETE {MONTH} {YEAR} HAUSVERWALTUNG MUELLER", day: 1, amount: -95000 },
  { desc: "STADTWERKE STROM GAS", day: 3, amount: -10800 },
  { desc: "VODAFONE GMBH MOBILFUNK", day: 5, amount: -3999 },
  { desc: "NETFLIX.COM/BILL", day: 12, amount: -1799 },
  { desc: "SPOTIFY AB BY ADYEN", day: 14, amount: -999 },
  { desc: "OPENAI LLC SUBSCRIPTION", day: 18, amount: -2200 },
  { desc: "URBAN SPORTS CLUB GMBH", day: 7, amount: -5900 },
  { desc: "GITHUB INC", day: 22, amount: -400 },
];

// --- Quarterly bills ---
const QUARTERLY: { desc: string; day: number; amount: number; months: number[] }[] = [
  { desc: "RUNDFUNK ARD ZDF DEUTSCHLANDRADIO", day: 15, amount: -5508, months: [1, 4, 7, 10] },
  { desc: "ALLIANZ HAUSRATVERSICHERUNG", day: 20, amount: -8950, months: [3, 6, 9, 12] },
];

// --- Intro-pricing subscription (months 1-2 cheap, months 3+ full price) ---
// Trips the new bimodal amount check in recurring.zig — the price jumped halfway
// through history but the most recent N entries are stable at the full price.
const INTRO_PRICED = {
  desc: "DISNEY+ STREAMING",
  day: 9,
  introMonths: 2,
  introAmount: -499,
  fullAmount: -1299,
};

// --- Stale subscription (stopped 5 months ago) ---
// Should appear in the merchant bucket but get marked inactive by the new
// staleness filter, so it does not pollute the Wiederkehrend page with a
// fake "500 days overdue" entry.
const STALE_SUB = {
  desc: "MCFIT FITNESSSTUDIO MUC",
  day: 4,
  amount: -2499,
  activeForFirstNMonths: 3, // present in first 3 of 8 months, then stops
};

// --- Weekly/frequent (variable amount + count) ---
const FREQUENT: { desc: string; min: number; max: number; freq: [number, number] }[] = [
  { desc: "REWE SAGT DANKE {id}//MUENCHEN/DE", min: -7500, max: -1800, freq: [4, 6] },
  { desc: "LIDL DIENSTL SAGT DANKE {id}", min: -4500, max: -1500, freq: [2, 4] },
  { desc: "EDEKA CENTER {id}", min: -6500, max: -1200, freq: [2, 3] },
  { desc: "ALDI SUED SAGT DANKE", min: -5500, max: -1000, freq: [1, 2] },
  { desc: "DM DROGERIEMARKT SAGT DANKE", min: -3000, max: -700, freq: [1, 2] },
  { desc: "ROSSMANN {id}", min: -2500, max: -600, freq: [0, 2] },
  { desc: "BACKEREI MUELLER {id}", min: -800, max: -250, freq: [2, 4] },
];

// --- Occasional ---
const OCCASIONAL: { desc: string; min: number; max: number; chance: number }[] = [
  { desc: "LIEFERANDO.DE ORDER {id}", min: -3500, max: -1200, chance: 0.6 },
  { desc: "AMAZON EU SARL DE", min: -12000, max: -1500, chance: 0.7 },
  { desc: "APOTHEKE AM MARKT {id}", min: -3000, max: -500, chance: 0.4 },
  { desc: "DB VERTRIEB GMBH FAHRKARTE", min: -4500, max: -1500, chance: 0.5 },
  { desc: "SHELL TANKSTELLE {id}", min: -7500, max: -3500, chance: 0.4 },
  { desc: "ARAL TANKSTELLE", min: -7500, max: -3500, chance: 0.3 },
  { desc: "BURGER KING #{id}", min: -2200, max: -800, chance: 0.5 },
  { desc: "RESTAURANT TRATTORIA DA LUIGI", min: -6500, max: -2500, chance: 0.4 },
  { desc: "PAYPAL .EBAY KLEINANZEIGEN", min: -8500, max: -1500, chance: 0.2 },
];

// --- Seasonal one-shots ---
const SEASONAL: { month: number; desc: string; min: number; max: number }[] = [
  { month: 12, desc: "AMAZON EU SARL DE GESCHENK", min: -25000, max: -8000 },
  { month: 12, desc: "DOUGLAS PARFUEMERIE", min: -8000, max: -3500 },
  { month: 7, desc: "BOOKING.COM B.V.", min: -45000, max: -15000 },
  { month: 8, desc: "RYANAIR FR", min: -22000, max: -8000 },
  { month: 4, desc: "IKEA EINRICHTUNGSHAUS", min: -18000, max: -4500 },
];

const MONTH_NAMES = [
  "",
  "JANUAR",
  "FEBRUAR",
  "MAERZ",
  "APRIL",
  "MAI",
  "JUNI",
  "JULI",
  "AUGUST",
  "SEPTEMBER",
  "OKTOBER",
  "NOVEMBER",
  "DEZEMBER",
];

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** Random amount in cents, ±50ct jitter to avoid suspiciously round numbers. */
function randAmount(min: number, max: number): number {
  return randInt(min, max) + randInt(0, 99) - 50;
}

function formatDate(year: number, month: number, day: number): string {
  return `${String(day).padStart(2, "0")}.${String(month).padStart(2, "0")}.${year}`;
}

function formatAmount(cents: number): string {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const eur = Math.floor(abs / 100);
  const ct = abs % 100;
  return `${sign}${eur.toLocaleString("de-DE")},${String(ct).padStart(2, "0")}`;
}

function daysInMonth(year: number, month: number): number {
  return new Date(year, month, 0).getDate();
}

interface CsvRow {
  date: string;
  desc: string;
  amount: string;
  sortKey: number; // yyyymmdd descending sort
}

interface MonthCursor {
  year: number;
  month: number;
  /** 0 = current month, 1 = previous, … MONTHS_OF_HISTORY-1 = oldest */
  offsetFromNow: number;
}

export function generateDemoCSV(): { csv: string; months: MonthCursor[] } {
  const now = new Date();
  const rows: CsvRow[] = [];
  const months: MonthCursor[] = [];

  for (let offset = 0; offset < MONTHS_OF_HISTORY; offset++) {
    const d = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    const year = d.getFullYear();
    const month = d.getMonth() + 1;
    const maxDay = daysInMonth(year, month);
    const monthName = MONTH_NAMES[month];
    months.push({ year, month, offsetFromNow: offset });

    // Stable monthly recurring
    for (const tx of STABLE_MONTHLY) {
      const day = Math.min(tx.day + randInt(-1, 1), maxDay);
      const desc = tx.desc.replace("{MONTH}", monthName).replace("{YEAR}", String(year));
      // Light jitter on income so "vs Vormonat" delta is non-zero
      const jitter = tx.amount > 0 ? randInt(-5000, 5000) : 0;
      rows.push({
        date: formatDate(year, month, day),
        desc,
        amount: formatAmount(tx.amount + jitter),
        sortKey: year * 10000 + month * 100 + day,
      });
    }

    // Quarterly bills
    for (const tx of QUARTERLY) {
      if (tx.months.includes(month)) {
        const day = Math.min(tx.day + randInt(-2, 2), maxDay);
        rows.push({
          date: formatDate(year, month, day),
          desc: tx.desc,
          amount: formatAmount(tx.amount),
          sortKey: year * 10000 + month * 100 + day,
        });
      }
    }

    // Intro-priced subscription: cheap for first 2 months from oldest, full price after
    {
      const monthsFromStart = MONTHS_OF_HISTORY - 1 - offset;
      const amount =
        monthsFromStart < INTRO_PRICED.introMonths
          ? INTRO_PRICED.introAmount
          : INTRO_PRICED.fullAmount;
      const day = Math.min(INTRO_PRICED.day + randInt(-1, 1), maxDay);
      rows.push({
        date: formatDate(year, month, day),
        desc: INTRO_PRICED.desc,
        amount: formatAmount(amount),
        sortKey: year * 10000 + month * 100 + day,
      });
    }

    // Stale sub: present only in the oldest activeForFirstNMonths
    {
      const monthsFromStart = MONTHS_OF_HISTORY - 1 - offset;
      if (monthsFromStart < STALE_SUB.activeForFirstNMonths) {
        const day = Math.min(STALE_SUB.day + randInt(-1, 1), maxDay);
        rows.push({
          date: formatDate(year, month, day),
          desc: STALE_SUB.desc,
          amount: formatAmount(STALE_SUB.amount),
          sortKey: year * 10000 + month * 100 + day,
        });
      }
    }

    // Frequent
    for (const tx of FREQUENT) {
      const count = randInt(tx.freq[0], tx.freq[1]);
      for (let i = 0; i < count; i++) {
        const day = randInt(1, maxDay);
        const id = String(randInt(10000, 99999));
        const desc = tx.desc.replace("{id}", id);
        const cents = randAmount(tx.min, tx.max);
        rows.push({
          date: formatDate(year, month, day),
          desc,
          amount: formatAmount(cents),
          sortKey: year * 10000 + month * 100 + day,
        });
      }
    }

    // Occasional (probability per item)
    for (const tx of OCCASIONAL) {
      if (Math.random() < tx.chance) {
        const day = randInt(5, maxDay);
        const id = String(randInt(10000, 99999));
        const desc = tx.desc.replace("{id}", id);
        const cents = randAmount(tx.min, tx.max);
        rows.push({
          date: formatDate(year, month, day),
          desc,
          amount: formatAmount(cents),
          sortKey: year * 10000 + month * 100 + day,
        });
      }
    }

    // Seasonal
    for (const tx of SEASONAL) {
      if (tx.month === month) {
        const day = randInt(5, maxDay - 5);
        const cents = randAmount(tx.min, tx.max);
        rows.push({
          date: formatDate(year, month, day),
          desc: tx.desc,
          amount: formatAmount(cents),
          sortKey: year * 10000 + month * 100 + day,
        });
      }
    }
  }

  // Sort descending by date (Comdirect export order)
  rows.sort((a, b) => b.sortKey - a.sortKey);

  const header = `"Buchungstag";"Wertstellung (Valuta)";"Vorgang";"Buchungstext";"Umsatz in EUR"`;
  const lines = rows.map((r) => `"${r.date}";"${r.date}";"Lastschrift";"${r.desc}";"${r.amount}"`);

  return {
    csv: header + "\n" + lines.join("\n") + "\n",
    months,
  };
}

export async function loadDemoData(): Promise<ImportResult> {
  const { csv, months } = generateDemoCSV();
  const encoded = new TextEncoder().encode(csv);
  const result = await importCsv(encoded.buffer as ArrayBuffer);
  autoCategorize();
  // Populate /recurring + /analysis right away so the demo lands on cards
  // that have data instead of "Erkennen?" CTAs.
  detectRecurring();
  for (const m of months) {
    takeSnapshot(m.year, m.month);
  }
  await opfsSave();
  localStorage.setItem(LS_DEMO_LOADED, "true");
  return result;
}

export function isDemoLoaded(): boolean {
  return localStorage.getItem(LS_DEMO_LOADED) === "true";
}

export function clearDemoFlag(): void {
  localStorage.removeItem(LS_DEMO_LOADED);
}
