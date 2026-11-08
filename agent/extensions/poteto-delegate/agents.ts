import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

export interface AgentDef {
	name: string;
	aliases: string[];
	description: string;
	tools: string[];
	readonly: boolean;
	advertise: boolean;
	defaultReads: string[];
	prompt: string;
	file: string;
}

const TOOL_NAMES = new Set([
	"read",
	"bash",
	"grep",
	"find",
	"ls",
	"edit",
	"write",
	"powershell",
]);

export function agentDir(): string {
	const fromEnv = process.env.PI_CODING_AGENT_DIR;
	if (fromEnv) {
		if (fromEnv === "~") return homedir();
		if (fromEnv.startsWith("~/")) return join(homedir(), fromEnv.slice(2));
		return fromEnv;
	}
	return join(homedir(), ".pi", "agent");
}

function splitList(value: string | undefined): string[] {
	if (!value) return [];
	return value
		.split(",")
		.map((part) => part.trim())
		.filter(Boolean);
}

function unquote(value: string): string {
	const trimmed = value.trim();
	if (
		(trimmed.startsWith('"') && trimmed.endsWith('"')) ||
		(trimmed.startsWith("'") && trimmed.endsWith("'"))
	) {
		return trimmed.slice(1, -1);
	}
	return trimmed;
}

interface ParsedFile {
	frontmatter: Record<string, string>;
	body: string;
}

function parseFrontmatter(content: string): ParsedFile {
	const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(content);
	if (!match) return { frontmatter: {}, body: content.trim() };
	const frontmatter: Record<string, string> = {};
	for (const line of match[1].split(/\r?\n/)) {
		if (!line.trim() || line.trimStart().startsWith("#")) continue;
		const colon = line.indexOf(":");
		if (colon <= 0) continue;
		frontmatter[line.slice(0, colon).trim()] = unquote(line.slice(colon + 1));
	}
	return { frontmatter, body: content.slice(match[0].length).trim() };
}

export function parseAgentFile(file: string): AgentDef | null {
	const content = readFileSync(file, "utf-8");
	const { frontmatter, body } = parseFrontmatter(content);
	const name =
		frontmatter.name?.trim() || basename(file).replace(/\.md$/i, "").trim();
	if (!name || !body) return null;

	const declared = splitList(frontmatter.tools);
	const tools = declared.filter((tool) => TOOL_NAMES.has(tool));
	const readonly =
		frontmatter.acceptanceRole === "read-only" ||
		(declared.length > 0 && !declared.includes("edit") && !declared.includes("write"));

	return {
		name,
		aliases: splitList(frontmatter.aliases),
		description: frontmatter.description ?? "",
		tools: tools.length > 0 ? tools : ["read", "grep", "find", "ls", "bash"],
		readonly,
		advertise: frontmatter.advertise === "true",
		defaultReads: splitList(frontmatter.defaultReads),
		prompt: body,
		file,
	};
}

function markdownFiles(dir: string): string[] {
	if (!existsSync(dir)) return [];
	let entries: string[];
	try {
		entries = readdirSync(dir);
	} catch {
		return [];
	}
	const files: string[] = [];
	for (const entry of entries.sort()) {
		if (entry.startsWith("_") || entry.startsWith(".")) continue;
		const full = join(dir, entry);
		let isDir = false;
		try {
			isDir = statSync(full).isDirectory();
		} catch {
			continue;
		}
		if (isDir) {
			let nested: string[];
			try {
				nested = readdirSync(full);
			} catch {
				continue;
			}
			for (const child of nested.sort()) {
				if (!child.toLowerCase().endsWith(".md")) continue;
				if (child.startsWith("_") || child === "CONVENTIONS.md") continue;
				files.push(join(full, child));
			}
			continue;
		}
		if (!entry.toLowerCase().endsWith(".md")) continue;
		if (entry === "CONVENTIONS.md") continue;
		files.push(full);
	}
	return files;
}

export function loadAgents(cwd: string): Map<string, AgentDef> {
	const roots = [join(cwd, ".pi", "agents"), join(agentDir(), "agents")];
	const registry = new Map<string, AgentDef>();
	for (const root of roots) {
		for (const file of markdownFiles(root)) {
			let def: AgentDef | null;
			try {
				def = parseAgentFile(file);
			} catch {
				continue;
			}
			if (!def) continue;
			if (!registry.has(def.name)) registry.set(def.name, def);
			for (const alias of def.aliases) {
				if (!registry.has(alias)) registry.set(alias, def);
			}
		}
	}
	return registry;
}

export function uniqueAgents(registry: Map<string, AgentDef>): AgentDef[] {
	const seen = new Set<string>();
	const out: AgentDef[] = [];
	for (const def of registry.values()) {
		if (seen.has(def.name)) continue;
		seen.add(def.name);
		out.push(def);
	}
	return out.sort((a, b) => a.name.localeCompare(b.name));
}

export function childTools(def: AgentDef): string[] {
	return def.readonly
		? def.tools.filter((tool) => tool !== "edit" && tool !== "write")
		: [...def.tools];
}
