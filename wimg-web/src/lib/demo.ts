import { importCsv, autoCategorize, type ImportResult } from "$lib/wasm";
import { LS_DEMO_LOADED } from "$lib/config";

// --- Fixed monthly transactions (day 1-5) ---
const FIXED_MONTHLY = [
  { desc: "GEHALT {MONTH} 2026 ARBEITGEBER GMBH", amount: 325000 },
  { desc: "MIETE {MONTH} 2026 HAUSVERWALTUNG", amount: -95000 },
  { desc: "STADTWERKE STROM GAS", min: -11500, max: -9500 },
  { desc: "NETFLIX.COM", amount: -1799 },
  { desc: "SPOTIFY AB", amount: -999 },
  { desc: "ALLIANZ VERSICHERUNG", amount: -8950 },
  { desc: "GEZ BEITRAGSSERVICE", amount: -1836 },
  { desc: "VODAFONE GMBH MOBILFUNK", amount: -3999 },
];

// --- Weekly/frequent transactions ---
const FREQUENT = [
  { desc: "REWE SAGT DANKE {id}//MUENCHEN/DE", min: -8500, max: -1500, freq: [3, 4] },
  { desc: "LIDL DIENSTL SAGT DANKE", min: -4500, max: -1200, freq: [2, 3] },
  { desc: "EDEKA CENTER {id}", min: -5500, max: -800, freq: [2, 3] },
  { desc: "DM DROGERIEMARKT SAGT DANKE", min: -2500, max: -500, freq: [1, 2] },
  { desc: "DB VERTRIEB GMBH", min: -4500, max: -1500, freq: [1, 2] },
];

// --- Occasional transactions ---
const OCCASIONAL = [
  { desc: "LIEFERANDO.DE", min: -3500, max: -1200 },
  { desc: "AMAZON EU SARL", min: -12000, max: -1500 },
  { desc: "ROSSMANN SAGT DANKE", min: -2000, max: -500 },
  { desc: "APOTHEKE AM MARKT", min: -3000, max: -500 },
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

function randAmount(min: number, max: number): number {
  // Return amount in cents, not round (add random cents)
  const base = randInt(min, max);
  return base + randInt(0, 99) - 50;
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
  sortKey: number; // yyyymmdd for sorting
}

export function generateDemoCSV(): string {
  const now = new Date();
  const rows: CsvRow[] = [];

  // Generate 3 months of data (current month and 2 prior)
  for (let offset = 0; offset < 3; offset++) {
    const d = new Date(now.getFullYear(), now.getMonth() - offset, 1);
    const year = d.getFullYear();
    const month = d.getMonth() + 1;
    const maxDay = daysInMonth(year, month);
    const monthName = MONTH_NAMES[month];

    // Fixed monthly (day 1-5)
    for (const tx of FIXED_MONTHLY) {
      const day = randInt(1, Math.min(5, maxDay));
      const desc = tx.desc.replace("{MONTH}", monthName);
      const cents = tx.amount ?? randAmount(tx.min!, tx.max!);
      rows.push({
        date: formatDate(year, month, day),
        desc,
        amount: formatAmount(cents),
        sortKey: year * 10000 + month * 100 + day,
      });
    }

    // Frequent (spread across month)
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

    // Occasional (0-2x per month)
    for (const tx of OCCASIONAL) {
      const count = randInt(0, 2);
      for (let i = 0; i < count; i++) {
        const day = randInt(5, maxDay);
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

  // Build CSV
  const header = `"Buchungstag";"Wertstellung (Valuta)";"Vorgang";"Buchungstext";"Umsatz in EUR"`;
  const lines = rows.map((r) => `"${r.date}";"${r.date}";"Lastschrift";"${r.desc}";"${r.amount}"`);

  return header + "\n" + lines.join("\n") + "\n";
}

export async function loadDemoData(): Promise<ImportResult> {
  const csv = generateDemoCSV();
  const encoded = new TextEncoder().encode(csv);
  const result = await importCsv(encoded.buffer as ArrayBuffer);
  autoCategorize();
  localStorage.setItem(LS_DEMO_LOADED, "true");
  return result;
}

export function isDemoLoaded(): boolean {
  return localStorage.getItem(LS_DEMO_LOADED) === "true";
}

export function clearDemoFlag(): void {
  localStorage.removeItem(LS_DEMO_LOADED);
}
