import { describe, it, expect } from "bun:test";
import { formatEurCompact, formatDateHeading } from "./format";

describe("formatEurCompact", () => {
  it("formats small amounts normally", () => {
    expect(formatEurCompact(50)).toContain("50");
  });

  it("uses k suffix for >= 1000", () => {
    expect(formatEurCompact(2616)).toBe("2,6k €");
  });

  it("handles exact thousands", () => {
    expect(formatEurCompact(1000)).toBe("1,0k €");
  });

  it("handles large numbers", () => {
    expect(formatEurCompact(25000)).toBe("25,0k €");
  });

  it("uses absolute value for negative amounts", () => {
    expect(formatEurCompact(-5000)).toBe("5,0k €");
  });

  it("formats 999 without k suffix", () => {
    const result = formatEurCompact(999);
    expect(result).not.toContain("k");
    expect(result).toContain("999");
  });

  it("handles 0", () => {
    const result = formatEurCompact(0);
    expect(result).toContain("0");
  });
});

describe("formatDateHeading", () => {
  it("shows 'Heute' for today", () => {
    const today = new Date();
    const iso = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
    expect(formatDateHeading(iso)).toContain("Heute");
  });

  it("shows 'Gestern' for yesterday", () => {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const iso = `${yesterday.getFullYear()}-${String(yesterday.getMonth() + 1).padStart(2, "0")}-${String(yesterday.getDate()).padStart(2, "0")}`;
    expect(formatDateHeading(iso)).toContain("Gestern");
  });

  it("shows weekday for other dates in same year", () => {
    // Pick a date that's definitely not today or yesterday
    const date = new Date();
    date.setDate(date.getDate() - 10);
    const iso = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
    const result = formatDateHeading(iso);
    expect(result).not.toContain("Heute");
    expect(result).not.toContain("Gestern");
    expect(result).toContain("·");
  });

  it("appends year for dates in a different year", () => {
    const result = formatDateHeading("2020-06-15");
    expect(result).toContain("2020");
  });
});
