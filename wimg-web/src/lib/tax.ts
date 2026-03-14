/**
 * Tax calculation logic for Anlage N (German tax return).
 * Pure functions — no side effects, no DOM, no stores.
 */

export interface TaxCategory {
  id: string;
  label: string;
  icon: string;
  color: string;
  textColor: string;
  keywords: string[];
}

export interface TaxConfig {
  year: number;
  km: number;
  workDays: number;
  homeofficeDays: number;
  excluded: string[];
  customKeywords: Record<string, string[]>; // categoryId → extra keywords
}

export const DEFAULT_TAX_CONFIG: TaxConfig = {
  year: new Date().getFullYear(),
  km: 0,
  workDays: 220,
  homeofficeDays: 0,
  excluded: [],
  customKeywords: {},
};

export const TAX_CATEGORIES: TaxCategory[] = [
  {
    id: "arbeitsmittel",
    label: "Arbeitsmittel",
    icon: "💻",
    color: "bg-blue-100",
    textColor: "text-blue-700",
    keywords: [
      "apple",
      "mediamarkt",
      "saturn",
      "büro",
      "computer",
      "laptop",
      "monitor",
      "tastatur",
      "logitech",
      "dell",
      "lenovo",
      "thinkpad",
      "macbook",
      "ipad",
    ],
  },
  {
    id: "fortbildung",
    label: "Fortbildung",
    icon: "📚",
    color: "bg-emerald-100",
    textColor: "text-emerald-700",
    keywords: [
      "udemy",
      "coursera",
      "kurs",
      "seminar",
      "weiterbildung",
      "fortbildung",
      "schulung",
      "linkedin learning",
      "pluralsight",
    ],
  },
  {
    id: "fachliteratur",
    label: "Fachliteratur",
    icon: "📖",
    color: "bg-violet-100",
    textColor: "text-violet-700",
    keywords: ["fachbuch", "o'reilly", "manning", "apress", "springer", "thalia fach"],
  },
  {
    id: "fahrtkosten",
    label: "Fahrtkosten",
    icon: "🚆",
    color: "bg-amber-100",
    textColor: "text-amber-700",
    keywords: [
      "deutsche bahn",
      "db fernverkehr",
      "db regio",
      "flixbus",
      "flixtrain",
      "bvg",
      "mvv",
      "hvv",
      "rheinbahn",
      "kvb",
    ],
  },
  {
    id: "versicherung",
    label: "Versicherungen",
    icon: "🛡️",
    color: "bg-rose-100",
    textColor: "text-rose-700",
    keywords: ["berufshaftpflicht", "rechtsschutz", "berufsunfähigkeit"],
  },
];

/**
 * Pendlerpauschale: 0.30€/km for first 20km, 0.38€/km beyond.
 */
export function calcPendlerpauschale(km: number, workDays: number): number {
  if (km <= 0 || workDays <= 0) return 0;
  const first20 = Math.min(km, 20) * 0.3;
  const beyond20 = Math.max(km - 20, 0) * 0.38;
  return (first20 + beyond20) * workDays;
}

/**
 * Homeoffice-Pauschale: 6€/day, max 210 days/year.
 */
export function calcHomeofficePauschale(days: number): number {
  return Math.min(Math.max(days, 0), 210) * 6;
}

/**
 * Get all keywords for a category (built-in + custom).
 */
export function getCategoryKeywords(
  category: TaxCategory,
  customKeywords: Record<string, string[]>,
): string[] {
  const custom = customKeywords[category.id] ?? [];
  return [...category.keywords, ...custom];
}

/**
 * Match a transaction description against tax categories.
 * Returns the first matching category, or null.
 */
export function matchTaxCategory(
  description: string,
  categories: TaxCategory[],
  customKeywords: Record<string, string[]>,
): TaxCategory | null {
  const lower = description.toLowerCase();
  for (const cat of categories) {
    const keywords = getCategoryKeywords(cat, customKeywords);
    if (keywords.some((kw) => lower.includes(kw))) {
      return cat;
    }
  }
  return null;
}
