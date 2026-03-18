#!/usr/bin/env bun
/**
 * Bank catalog drift checker.
 *
 * Compares the official FinTS institute CSV (from Deutsche Kreditwirtschaft)
 * against banks.zig to detect:
 * - Missing banks (have FinTS URL in CSV but not in our catalog)
 * - URL changes (same BLZ, different URL)
 * - Removed banks (in our catalog but no longer in CSV with a FinTS URL)
 *
 * Usage:
 *     bun scripts/check-bank-drift.ts path/to/fints_institute.csv
 *     bun scripts/check-bank-drift.ts path/to/fints_institute.csv --json-out drift-report.json
 */

import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { resolve, dirname } from "path";

interface CsvBank {
	blz: string;
	bic: string;
	name: string;
	url: string;
}

interface ZigBank {
	blz: string;
	bic: string;
	name: string;
	url: string;
}

function parseOfficialCsv(path: string): Map<string, CsvBank> {
	const banks = new Map<string, CsvBank>();

	// Try multiple encodings — official file is typically latin-1 or cp1252
	let content: string;
	try {
		const buf = readFileSync(path);
		// Try UTF-8 first, fall back to latin-1
		content = new TextDecoder("utf-8", { fatal: true }).decode(buf);
	} catch {
		const buf = readFileSync(path);
		content = new TextDecoder("latin1").decode(buf);
	}

	// Strip BOM
	if (content.charCodeAt(0) === 0xfeff) content = content.slice(1);

	const lines = content.split(/\r?\n/).filter(Boolean);
	if (lines.length === 0) throw new Error(`Empty file: ${path}`);

	// Detect delimiter
	const delimiter = lines[0].includes(";") ? ";" : ",";
	const headers = lines[0].split(delimiter).map((h) => h.trim());

	// Map header names to column indices
	let blzIdx = -1;
	let bicIdx = -1;
	let nameIdx = -1;
	let urlIdx = -1;

	for (let i = 0; i < headers.length; i++) {
		const h = headers[i].toLowerCase();
		if (h.includes("bankleitzahl") || h === "blz") blzIdx = i;
		else if (h === "bic" || h.includes("bic")) bicIdx = i;
		else if (h.includes("bezeichnung") || h.includes("name") || h.includes("institut"))
			nameIdx = i;
		else if (h.includes("url") || h.includes("pin/tan") || h.replace(/[-\s]/g, "").includes("fints"))
			urlIdx = i;
	}

	if (blzIdx === -1) {
		throw new Error(`Cannot find BLZ column. Available: ${headers.join(", ")}`);
	}

	for (let i = 1; i < lines.length; i++) {
		const cols = lines[i].split(delimiter).map((c) => c.trim());
		let blz = cols[blzIdx] ?? "";
		if (!blz || !/^\d+$/.test(blz)) continue;
		blz = blz.padStart(8, "0");

		const url = (cols[urlIdx] ?? "").trim();
		if (!url || !url.startsWith("http")) continue;

		const normalizedUrl = url.replace(/\/+$/, "");
		const bic = (cols[bicIdx] ?? "").trim();
		const name = (cols[nameIdx] ?? "").trim();

		// Keep first occurrence per BLZ
		if (!banks.has(blz)) {
			banks.set(blz, { blz, bic, name, url: normalizedUrl });
		}
	}

	return banks;
}

function parseBanksZig(path: string): Map<string, ZigBank> {
	const text = readFileSync(path, "utf-8");
	const pattern = /makeBank\("(\d{8})",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"\)/g;
	const banks = new Map<string, ZigBank>();
	let m: RegExpExecArray | null;
	while ((m = pattern.exec(text)) !== null) {
		banks.set(m[1], {
			blz: m[1],
			bic: m[2],
			name: m[3],
			url: m[4].replace(/\/+$/, ""),
		});
	}
	return banks;
}

function normalizeUrl(url: string): string {
	return url.replace(/\/+$/, "").toLowerCase();
}

function checkDrift(csvBanks: Map<string, CsvBank>, zigBanks: Map<string, ZigBank>) {
	const missing: Array<{ blz: string; bic: string; name: string; url: string }> = [];
	const urlChanges: Array<{ blz: string; name: string; old_url: string; new_url: string }> = [];
	const removed: Array<{ blz: string; name: string; url: string }> = [];

	for (const [blz, cb] of [...csvBanks.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
		const zb = zigBanks.get(blz);
		if (!zb) {
			missing.push({ blz, bic: cb.bic, name: cb.name, url: cb.url });
		} else if (normalizeUrl(cb.url) !== normalizeUrl(zb.url)) {
			urlChanges.push({ blz, name: cb.name, old_url: zb.url, new_url: cb.url });
		}
	}

	for (const [blz, zb] of [...zigBanks.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
		if (!csvBanks.has(blz)) {
			removed.push({ blz, name: zb.name, url: zb.url });
		}
	}

	return { missing, urlChanges, removed };
}

function printReport(
	missing: ReturnType<typeof checkDrift>["missing"],
	urlChanges: ReturnType<typeof checkDrift>["urlChanges"],
	removed: ReturnType<typeof checkDrift>["removed"],
	csvCount: number,
	zigCount: number,
) {
	console.log(`Official CSV: ${csvCount} banks with FinTS URLs`);
	console.log(`banks.zig:    ${zigCount} banks\n`);

	if (!missing.length && !urlChanges.length && !removed.length) {
		console.log("No drift detected. banks.zig is up to date.");
		return;
	}

	if (missing.length) {
		console.log(`MISSING (${missing.length} banks in CSV but not in banks.zig):`);
		console.log("-".repeat(80));
		for (const b of missing.slice(0, 30)) {
			console.log(`  ${b.blz}  ${b.name.slice(0, 40).padEnd(40)}  ${b.url}`);
		}
		if (missing.length > 30) console.log(`  ... and ${missing.length - 30} more`);
		console.log();
	}

	if (urlChanges.length) {
		console.log(`URL CHANGES (${urlChanges.length} banks with different URLs):`);
		console.log("-".repeat(80));
		for (const b of urlChanges) {
			console.log(`  ${b.blz}  ${b.name.slice(0, 40)}`);
			console.log(`    old: ${b.old_url}`);
			console.log(`    new: ${b.new_url}`);
		}
		console.log();
	}

	if (removed.length) {
		console.log(`REMOVED (${removed.length} banks in banks.zig but not in CSV):`);
		console.log("-".repeat(80));
		for (const b of removed.slice(0, 30)) {
			console.log(`  ${b.blz}  ${b.name.slice(0, 40).padEnd(40)}  ${b.url}`);
		}
		if (removed.length > 30) console.log(`  ... and ${removed.length - 30} more`);
		console.log();
	}
}

// --- Main ---

const args = process.argv.slice(2);
let csvPath: string | null = null;
let jsonOut: string | null = null;

for (let i = 0; i < args.length; i++) {
	if (args[i] === "--json-out" && args[i + 1]) {
		jsonOut = args[++i];
	} else if (!args[i].startsWith("-")) {
		csvPath = args[i];
	}
}

if (!csvPath) {
	console.error("Usage: bun scripts/check-bank-drift.ts path/to/fints_institute.csv [--json-out report.json]");
	process.exit(1);
}

const repoRoot = resolve(dirname(new URL(import.meta.url).pathname), "..");
const banksZigPath = resolve(repoRoot, "libwimg/src/banks.zig");

const csvBanks = parseOfficialCsv(csvPath);
const zigBanks = parseBanksZig(banksZigPath);

console.log(`Parsed ${csvBanks.size} banks from CSV, ${zigBanks.size} from banks.zig\n`);

const { missing, urlChanges, removed } = checkDrift(csvBanks, zigBanks);
printReport(missing, urlChanges, removed, csvBanks.size, zigBanks.size);

if (jsonOut) {
	const report = {
		summary: {
			csv_count: csvBanks.size,
			zig_count: zigBanks.size,
			missing_count: missing.length,
			url_change_count: urlChanges.length,
			removed_count: removed.length,
		},
		missing,
		url_changes: urlChanges,
		removed,
	};
	const outPath = resolve(repoRoot, jsonOut);
	mkdirSync(dirname(outPath), { recursive: true });
	writeFileSync(outPath, JSON.stringify(report, null, 2));
	console.log(`JSON report written: ${outPath}`);
}
