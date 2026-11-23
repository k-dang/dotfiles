// Historian reads Main's saved session on request. Pure functions over session entries, so tests need no Pi.

export interface HistoryRequest {
	query?: string;
	entry?: string;
	page?: number;
	offset?: number;
}

interface HistoryEntry {
	id: string;
	type: string;
	message?: { role?: string; content?: unknown };
	summary?: string;
}

interface HistoryRecord {
	id: string;
	speaker: string;
	text: string;
}

const PAGE = 8;
const EXCERPT = 400;
const READ = 4000;

function textOf(content: unknown) {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content.filter((part) => part?.type === "text" && typeof part.text === "string").map((part) => part.text).join("\n");
}

/** Visible conversation text on the active branch, including originals before compaction. No tool output or thinking. */
export function historyRecords(branch: readonly HistoryEntry[]): HistoryRecord[] {
	const records: HistoryRecord[] = [];
	for (const entry of branch) {
		if (entry.type === "message" && (entry.message?.role === "user" || entry.message?.role === "assistant")) {
			const text = textOf(entry.message.content).trim();
			if (text) records.push({ id: entry.id, speaker: entry.message.role === "user" ? "User" : "Main", text });
		} else if ((entry.type === "compaction" || entry.type === "branch_summary") && entry.summary?.trim()) {
			records.push({ id: entry.id, speaker: entry.type === "compaction" ? "Compaction summary" : "Branch summary", text: entry.summary.trim() });
		}
	}
	return records;
}

function excerpt(text: string, needle?: string) {
	const at = needle ? Math.max(0, text.toLowerCase().indexOf(needle) - EXCERPT / 3) : 0;
	const body = text.slice(at, at + EXCERPT).replace(/\s+/g, " ").trim();
	return `${at > 0 ? "…" : ""}${body}${at + EXCERPT < text.length ? "…" : ""}`;
}

export function searchHistory(records: readonly HistoryRecord[], { query, entry, page = 0, offset = 0 }: HistoryRequest) {
	if (entry !== undefined) {
		const record = records.find((item) => item.id === entry);
		if (!record) throw new Error(`No entry ${entry} on Main's active branch.`);
		return {
			entry: record.id, speaker: record.speaker, offset, length: record.text.length,
			text: record.text.slice(offset, offset + READ), more: offset + READ < record.text.length,
		};
	}
	const needle = query?.trim().toLowerCase() || undefined;
	// A search reads in conversation order; a bare listing starts with the newest entries.
	const hits = needle ? records.filter((item) => item.text.toLowerCase().includes(needle)) : [...records].reverse();
	const start = page * PAGE;
	return {
		total: hits.length, page, more: start + PAGE < hits.length,
		entries: hits.slice(start, start + PAGE).map(({ id, speaker, text }) => ({ id, speaker, text: excerpt(text, needle) })),
	};
}
