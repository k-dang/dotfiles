import { randomUUID } from "node:crypto";
import {
	appendFileSync, closeSync, fstatSync, mkdirSync, openSync,
	readFileSync, readSync, readdirSync, renameSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { join } from "node:path";

export interface MainText {
	kind: "prompt" | "reply";
	text: string;
}

export interface AgentLink {
	mailbox: string;
	name: string;
	job: string;
	offset: number;
	/** Main's session file. Set for Historian, which reads history on request instead of following the feed. */
	history?: string;
}

interface Finding {
	name: string;
	number: number;
	text: string;
}

function missing(error: unknown) {
	return (error as NodeJS.ErrnoException).code === "ENOENT";
}

function followerAlive(file: string) {
	try {
		if ((JSON.parse(readFileSync(file, "utf8")) as AgentLink).history) return false;
	} catch (error) {
		if (!missing(error)) throw error;
		return false;
	}
	let pid: number;
	try {
		pid = Number(readFileSync(`${file}.pid`, "utf8"));
	} catch (error) {
		if (!missing(error)) throw error;
		try {
			// Herdr has accepted the split, but Pi may still be starting up.
			return Date.now() - statSync(file).mtimeMs < 120_000;
		} catch (error) {
			if (!missing(error)) throw error;
			return false;
		}
	}
	if (!Number.isSafeInteger(pid) || pid <= 0) return false;
	try {
		process.kill(pid, 0);
		return true;
	} catch (error) {
		return (error as NodeJS.ErrnoException).code === "EPERM";
	}
}

export class Mailbox {
	readonly transcript: string;
	private readonly inbox: string;
	private readonly dir: string;

	constructor(dir: string) {
		this.dir = dir;
		this.transcript = join(dir, "main.jsonl");
		this.inbox = join(dir, "to-main");
	}

	get hasFollowers() {
		try {
			return readdirSync(this.dir).some((name) => /^[a-f0-9-]{36}\.json$/.test(name) && followerAlive(join(this.dir, name)));
		} catch (error) {
			if (!missing(error)) throw error;
			return false;
		}
	}

	link(name: string, job: string, history?: string) {
		mkdirSync(this.inbox, { recursive: true, mode: 0o700 });
		if (!this.hasFollowers) writeFileSync(this.transcript, "", { mode: 0o600 });
		const file = join(this.dir, `${randomUUID()}.json`);
		const link: AgentLink = { mailbox: this.dir, name, job, offset: statSync(this.transcript).size, history };
		writeFileSync(file, JSON.stringify(link), { flag: "wx", mode: 0o600 });
		return file;
	}

	static attach(file: string) {
		const pid = `${file}.pid`;
		const temp = `${pid}.tmp`;
		writeFileSync(temp, String(process.pid), { mode: 0o600 });
		renameSync(temp, pid);
	}

	static detach(file: string) {
		rmSync(file, { force: true });
		rmSync(`${file}.pid`, { force: true });
	}

	publish(note: MainText) {
		appendFileSync(this.transcript, JSON.stringify(note) + "\n");
	}

	read(offset: number): { offset: number; notes: MainText[] } {
		const fd = openSync(this.transcript, "r");
		try {
			const size = fstatSync(fd).size - offset;
			if (size < 0) throw new Error("Main's conversation log was truncated.");
			if (size === 0) return { offset, notes: [] };
			const bytes = Buffer.alloc(size);
			const count = readSync(fd, bytes, 0, size, offset);
			if (count === 0) return { offset, notes: [] };
			const end = bytes.lastIndexOf(10, count - 1);
			if (end === -1) return { offset, notes: [] };
			const notes = bytes.subarray(0, end).toString("utf8").split("\n").map((line) => JSON.parse(line));
			return { offset: offset + end + 1, notes };
		} finally {
			closeSync(fd);
		}
	}

	enqueue(finding: Finding) {
		const id = `${Date.now()}-${randomUUID()}.json`;
		const temp = join(this.inbox, `${id}.tmp`);
		// Each writer publishes its own record. Main only ever sees complete files.
		writeFileSync(temp, JSON.stringify(finding), { flag: "wx", mode: 0o600 });
		renameSync(temp, join(this.inbox, id));
	}

	pending() {
		try {
			return readdirSync(this.inbox).filter((id) => /^\d+-[a-f0-9-]+\.json$/.test(id)).sort().map((id) => ({
				id, ...JSON.parse(readFileSync(join(this.inbox, id), "utf8")) as Finding,
			}));
		} catch (error) {
			if (!missing(error)) throw error;
			return [];
		}
	}

	acknowledge(ids: string[]) {
		for (const id of ids) {
			if (/^\d+-[a-f0-9-]+\.json$/.test(id)) rmSync(join(this.inbox, id), { force: true });
		}
	}
}
