import { spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { AgentDef } from "./agents.ts";

export const OUT_DIR = join(tmpdir(), "poteto-delegate");
export const SESSION_DIR = join(OUT_DIR, "sessions");

/**
 * A child inherits `BILLION_CONTEXT_PROXY` from the parent. When the parent runs
 * billion-context inline, that value is the in-process sentinel
 * `http://billion-context.inline`, which no child process can ever reach, so the
 * child attaches to a phantom lane and its compress/decompress/search_context/
 * acp_status tools silently fail to register. Dropping the variable makes the
 * child arm its own lane. A real proxy origin (http://host:port) is a reachable
 * server and is passed through untouched.
 */
const INLINE_PROXY = "http://billion-context.inline";

/**
 * `--tools` is an allowlist: naming tools drops everything else, including the
 * four ACP compression tools billion-context registers on demand. They are
 * appended so a delegate can still compress its own context.
 */
export const ACP_TOOLS = ["compress", "decompress", "search_context", "acp_status"];

function childEnv(depth: number, maxDepth: number): NodeJS.ProcessEnv {
	const env: NodeJS.ProcessEnv = {
		...process.env,
		POTETO_DELEGATE_DEPTH: String(depth + 1),
		POTETO_DELEGATE_MAX_DEPTH: String(maxDepth),
	};
	if (env.BILLION_CONTEXT_PROXY === INLINE_PROXY) delete env.BILLION_CONTEXT_PROXY;
	delete env.PI_SESSION_FILE;
	delete env.PI_SESSION_ID;
	return env;
}

export type RunStatus = "running" | "completed" | "failed" | "cancelled";

export interface Run {
	runId: string;
	agent: string;
	status: RunStatus;
	task: string;
	cwd: string;
	startedAt: number;
	finishedAt?: number;
	output: string;
	error?: string;
	sessionFile?: string;
	child?: ReturnType<typeof spawn>;
}

export const runs = new Map<string, Run>();

const PI_PACKAGE_REL = join(
	"@earendil-works",
	"pi-coding-agent",
	"dist",
	"bundle",
	"cli.js",
);

function probeUp(argPath: string): string | null {
	let dir = dirname(argPath);
	for (;;) {
		const candidate = join(dir, "node_modules", PI_PACKAGE_REL);
		if (existsSync(candidate)) return candidate;
		const parent = dirname(dir);
		if (parent === dir) return null;
		dir = parent;
	}
}

export function resolvePiCli(): string {
	const explicit = process.env.PI_CLI_PATH;
	if (explicit && existsSync(explicit)) return explicit;
	const argv1 = process.argv[1] ?? "";
	if (existsSync(argv1)) {
		const probed = probeUp(argv1);
		if (probed) return probed;
	}
	const global = join(
		dirname(dirname(process.execPath)),
		"lib",
		"node_modules",
		PI_PACKAGE_REL,
	);
	if (existsSync(global)) return global;
	return argv1;
}

/**
 * The role prompt is the agent file body plus the files it declares it always
 * reads. Paths that no longer exist are dropped rather than passed on as a
 * pointer to nothing.
 */
export function buildRolePrompt(def: AgentDef): string {
	const reads = def.defaultReads
		.filter((file) => existsSync(file))
		.map((file) => `- \`${file}\``);
	if (reads.length === 0) return def.prompt;
	return `${def.prompt}\n\nRead these before you start:\n${reads.join("\n")}`;
}

export interface LaunchOptions {
	def: AgentDef;
	task: string;
	cwd: string;
	model?: string;
	thinkingLevel?: string;
	tools: string[];
	depth: number;
	maxDepth: number;
	onFinish: (run: Run) => void;
}

function newRunId(): string {
	return `pt_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

export function launch(opts: LaunchOptions): Run {
	const runId = newRunId();
	mkdirSync(SESSION_DIR, { recursive: true });

	const sessionFile = join(SESSION_DIR, `${runId}.jsonl`);
	const run: Run = {
		runId,
		agent: opts.def.name,
		status: "running",
		task: opts.task,
		cwd: opts.cwd,
		startedAt: Date.now(),
		output: "",
		sessionFile,
	};
	runs.set(runId, run);

	const tmp = mkdtempSync(join(tmpdir(), "poteto-role-"));
	const promptFile = join(tmp, "role.md");
	writeFileSync(promptFile, buildRolePrompt(opts.def), "utf-8");

	const args: string[] = [
		"--mode",
		"json",
		"--session",
		sessionFile,
		"--session-dir",
		SESSION_DIR,
		"--append-system-prompt",
		promptFile,
		"--tools",
		[...new Set([...opts.tools, ...ACP_TOOLS])].join(","),
	];
	if (opts.model) args.push("--model", opts.model);
	if (opts.thinkingLevel) args.push("--thinking", opts.thinkingLevel);

	const child = spawn(process.execPath, [resolvePiCli(), ...args], {
		cwd: opts.cwd,
		env: childEnv(opts.depth, opts.maxDepth),
		stdio: ["pipe", "pipe", "pipe"],
		shell: false,
	});
	run.child = child;

	let stdout = "";
	let stderr = "";
	child.stdout?.setEncoding("utf-8");
	child.stderr?.setEncoding("utf-8");
	child.stdout?.on("data", (chunk: string) => {
		stdout += chunk;
	});
	child.stderr?.on("data", (chunk: string) => {
		stderr += chunk;
	});

	const finish = () => {
		run.finishedAt = Date.now();
		try {
			writeFileSync(
				join(OUT_DIR, `${runId}.out`),
				run.output || run.error || "",
				"utf-8",
			);
		} catch {
			// Durable copy is a convenience; the in-memory run still has the text.
		}
		opts.onFinish(run);
	};

	child.on("error", (err) => {
		if (run.status === "running") run.status = "failed";
		run.error = String(err);
		finish();
	});

	child.on("close", (code, signal) => {
		if (run.status === "cancelled") {
			finish();
			return;
		}
		const text = collectFinalText(stdout);
		run.output = text;
		if (code === 0 && text.trim()) {
			run.status = "completed";
		} else {
			run.status = "failed";
			run.error =
				stderr.trim() ||
				(code === null
					? `killed by ${signal ?? "signal"}`
					: `exit ${code} with no assistant output`);
		}
		finish();
	});

	child.stdin?.once("error", () => {
		// Child exited before reading the prompt; the close handler reports it.
	});
	child.stdin?.end(opts.task, "utf-8");
	return run;
}

interface JsonEvent {
	type?: string;
	message?: { role?: string; content?: unknown };
}

function textFromContent(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content) {
		if (!block || typeof block !== "object") continue;
		const typed = block as { type?: string; text?: string };
		if (typed.type === "text" && typeof typed.text === "string") {
			parts.push(typed.text);
		}
	}
	return parts.join("");
}

/**
 * pi's `--mode json` stream repeats the assistant message on `turn_end` and
 * again inside `agent_end`, so read `turn_end` only. The last write wins: a
 * final turn that only calls tools contributes no text and leaves the previous
 * substantive answer in place.
 */
function collectFinalText(stdout: string): string {
	let last = "";
	for (const line of stdout.split("\n")) {
		const trimmed = line.trim();
		if (!trimmed.startsWith("{")) continue;
		let event: JsonEvent;
		try {
			event = JSON.parse(trimmed) as JsonEvent;
		} catch {
			continue;
		}
		if (event.type !== "turn_end") continue;
		if (event.message?.role !== "assistant") continue;
		const text = textFromContent(event.message.content).trim();
		if (text) last = text;
	}
	return last;
}

export function cancel(runId: string): boolean {
	const run = runs.get(runId);
	if (!run || run.status !== "running") return false;
	run.status = "cancelled";
	run.child?.kill("SIGTERM");
	return true;
}

export function elapsedSeconds(run: Run): number {
	return ((run.finishedAt ?? Date.now()) - run.startedAt) / 1000;
}

export function oneLine(text: string, limit = 100): string {
	const flat = text.replace(/\s+/g, " ").trim();
	return flat.length > limit ? `${flat.slice(0, limit - 1)}\u2026` : flat;
}
