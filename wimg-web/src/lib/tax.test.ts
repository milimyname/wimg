import { describe, it, expect } from "bun:test";
import {
  calcPendlerpauschale,
  calcHomeofficePauschale,
  matchTaxCategory,
  getCategoryKeywords,
  TAX_CATEGORIES,
} from "./tax";

describe("calcPendlerpauschale", () => {
  it("returns 0 for 0 km", () => {
    expect(calcPendlerpauschale(0, 220)).toBe(0);
  });

  it("returns 0 for 0 work days", () => {
    expect(calcPendlerpauschale(25, 0)).toBe(0);
  });

  it("returns 0 for negative values", () => {
    expect(calcPendlerpauschale(-5, 220)).toBe(0);
    expect(calcPendlerpauschale(25, -10)).toBe(0);
  });

  it("calculates correctly for <= 20km (0.30€/km only)", () => {
    // 15km × 0.30€ × 200 days = 900€
    expect(calcPendlerpauschale(15, 200)).toBeCloseTo(900);
  });

  it("calculates correctly at exactly 20km", () => {
    // 20km × 0.30€ × 220 days = 1320€
    expect(calcPendlerpauschale(20, 220)).toBeCloseTo(1320);
  });

  it("applies higher rate beyond 20km", () => {
    // (20 × 0.30 + 5 × 0.38) × 180 = (6 + 1.9) × 180 = 1422€
    expect(calcPendlerpauschale(25, 180)).toBeCloseTo(1422);
  });

  it("handles large distances", () => {
    // (20 × 0.30 + 80 × 0.38) × 220 = (6 + 30.4) × 220 = 8008€
    expect(calcPendlerpauschale(100, 220)).toBeCloseTo(8008);
  });
});

describe("calcHomeofficePauschale", () => {
  it("returns 0 for 0 days", () => {
    expect(calcHomeofficePauschale(0)).toBe(0);
  });

  it("calculates at 6€/day", () => {
    expect(calcHomeofficePauschale(45)).toBe(270);
  });

  it("caps at 210 days (1260€)", () => {
    expect(calcHomeofficePauschale(300)).toBe(1260);
    expect(calcHomeofficePauschale(210)).toBe(1260);
  });

  it("handles negative as 0", () => {
    expect(calcHomeofficePauschale(-5)).toBe(0);
  });
});

describe("matchTaxCategory", () => {
  it("matches arbeitsmittel keywords", () => {
    const result = matchTaxCategory("APPLE STORE BERLIN", TAX_CATEGORIES, {});
    expect(result?.id).toBe("arbeitsmittel");
  });

  it("matches case-insensitively", () => {
    const result = matchTaxCategory("UDEMY PAYMENT", TAX_CATEGORIES, {});
    expect(result?.id).toBe("fortbildung");
  });

  it("returns null for no match", () => {
    const result = matchTaxCategory("REWE MARKT BERLIN", TAX_CATEGORIES, {});
    expect(result).toBeNull();
  });

  it("returns first match (arbeitsmittel before others)", () => {
    const result = matchTaxCategory("Dell Monitor kaufen", TAX_CATEGORIES, {});
    expect(result?.id).toBe("arbeitsmittel");
  });

  it("matches custom keywords", () => {
    const custom = { fortbildung: ["skillshare"] };
    const result = matchTaxCategory("SKILLSHARE SUBSCRIPTION", TAX_CATEGORIES, custom);
    expect(result?.id).toBe("fortbildung");
  });

  it("custom keywords don't affect other categories", () => {
    const custom = { fortbildung: ["skillshare"] };
    const result = matchTaxCategory("REWE MARKT", TAX_CATEGORIES, custom);
    expect(result).toBeNull();
  });
});

describe("getCategoryKeywords", () => {
  it("returns built-in keywords when no custom", () => {
    const cat = TAX_CATEGORIES[0]; // arbeitsmittel
    const kws = getCategoryKeywords(cat, {});
    expect(kws).toEqual(cat.keywords);
  });

  it("appends custom keywords", () => {
    const cat = TAX_CATEGORIES[0];
    const custom = { arbeitsmittel: ["custom1", "custom2"] };
    const kws = getCategoryKeywords(cat, custom);
    expect(kws).toContain("custom1");
    expect(kws).toContain("custom2");
    expect(kws.length).toBe(cat.keywords.length + 2);
  });
});
