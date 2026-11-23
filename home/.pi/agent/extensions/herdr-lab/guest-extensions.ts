import { cp, lstat, mkdir, realpath } from "node:fs/promises";
import { basename, isAbsolute, join, relative, sep } from "node:path";
import { extensionSource } from "./scenario.ts";

async function statIfPresent(path: string) {
	return await lstat(path).catch(error => {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	});
}

async function entryPoint(source: string) {
	const file = await statIfPresent(source);
	if (file?.isFile() && /\.(?:[cm]?js|ts)$/i.test(source)) return source;
	if (file?.isDirectory()) {
		for (const name of ["index.ts", "index.js"]) {
			const entry = join(source, name);
			if ((await statIfPresent(entry))?.isFile()) return entry;
		}
	}
	throw new Error("Expected a regular .ts/.js/.mjs/.cjs file or a directory with index.ts or index.js (not a symlink).");
}

export async function stageExtensions(sources: string[], { project, agentDir, scratch }: {
	project: string; agentDir: string; scratch: string;
}): Promise<string[]> {
	const entries: string[] = [];
	for (const [index, spec] of sources.entries()) {
		try {
			if (!extensionSource(spec)) throw new Error("Expected a repo-relative path or installed:NAME.");
			if (spec.startsWith("installed:")) {
				const source = join(agentDir, "extensions", spec.slice("installed:".length));
				const entry = await entryPoint(source);
				const folder = join(scratch, "extensions", String(index + 1));
				const copy = join(folder, basename(source));
				await mkdir(folder, { recursive: true });
				await cp(source, copy, {
					recursive: true,
					filter: async (path) => {
						if (path !== source && [".git", "node_modules"].includes(basename(path))) return false;
						const stat = await lstat(path);
						if (!stat.isFile() && !stat.isDirectory()) throw new Error(`Not a regular file or directory: ${relative(source, path)}`);
						return true;
					},
				});
				entries.push(join(copy, relative(source, entry)));
			} else {
				const entry = await entryPoint(join(project, ...spec.split(/[\\/]/)));
				const path = await realpath(entry);
				const fromProject = relative(await realpath(project), path);
				if (isAbsolute(fromProject) || fromProject === ".." || fromProject.startsWith(`..${sep}`)) {
					throw new Error("Extension entry must be inside the HEAD snapshot.");
				}
				entries.push(path);
			}
		} catch (error) {
			const source = spec.startsWith("installed:") ? "the current Pi profile's extensions folder" : "the committed HEAD snapshot";
			throw new Error(`Cannot load ${JSON.stringify(spec)} from ${source}: ${error instanceof Error ? error.message : String(error)}`);
		}
	}
	return [...new Set(entries)];
}
