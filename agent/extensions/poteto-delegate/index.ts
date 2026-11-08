import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { type AgentDef, loadAgents, uniqueAgents } from "./agents.ts";
import { cancel, elapsedSeconds, launch, runs, type Run } from "./runner.ts";

const DEFAULT_MAX_DEPTH = 2;
const DEFAULT_WAIT_MS = 300_000;

function depth(): number {
	const raw = Number(process.env.POTETO_DELEGATE_DEPTH ?? "0");
	return Number.isFinite(raw) ? raw : 0;
}

function maxDepth(): number {
	const raw = Number(process.env.POTETO_DELEGATE_MAX_DEPTH ?? "");
	const parsed = Number(raw);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_MAX_DEPTH;
}

function catalog(agents: AgentDef[], onlyAdvertised: boolean): string {
	const list = onlyAdvertised ? agents.filter((a) => a.advertise) : agents;
	return list
		.map((a) => `- ${a.name}${a.readonly ? " (read-only)" : ""}: ${a.description}`)
		.join("\n");
}

function summary(run: Run): string {
	const lines = [
		`${run.agent} ${run.runId} ${run.status} in ${elapsedSeconds(run).toFixed(1)}s`,
	];
	if (run.status === "completed") {
		lines.push("", run.output);
	} else if (run.error) {
		lines.push("", run.error);
	}
	return lines.join("\n");
}

export default function (pi: ExtensionAPI) {
	let agents = loadAgents(process.cwd());

	const childToolNames = (def: AgentDef): string[] => {
		const base = [...def.tools];
		const nest = depth() + 1 < maxDepth();
		const names = def.readonly
			? base.filter((t) => t !== "edit" && t !== "write")
			: base;
		return nest
			? [
					...names,
					"poteto_delegate",
					"poteto_delegate_wait",
					"poteto_delegate_cancel",
				]
			: names;
	};

	const notify = (text: string) => {
		try {
			pi.sendMessage(
				{
					customType: "poteto-delegate",
					content: text,
					display: true,
				},
				{ deliverAs: "followUp", triggerTurn: true },
			);
		} catch {
			// The session may be shutting down; the durable .out file still has it.
		}
	};

	pi.on("session_start", async () => {
		agents = loadAgents(process.cwd());
	});

	pi.registerTool({
		name: "poteto_delegate",
		label: "Poteto Delegate",
		description: [
			"Spawn a named poteto agent in its own pi child process, with the agent's own system prompt and tool set.",
			`Agents come from <cwd>/.pi/agents/**/*.md and ${"~"}/.pi/agent/agents/**/*.md.`,
			"Async by default: the call returns a runId immediately and the result arrives as a follow-up message when the child finishes.",
			"Call poteto_delegate_wait to block for the result in the same turn.",
			"Nesting is capped, so a delegate cannot fan out forever.",
		].join(" "),
		promptSnippet: "Spawn a named poteto agent, async by default",
		promptGuidelines: [
			"Use poteto_delegate to hand work to a named poteto agent such as poteto-agent, pstack-why, or pstack-arena.",
			"Give poteto_delegate a self-contained brief with file pointers and line numbers, not inlined source.",
			"Call poteto_delegate_wait only when you need the result in this same turn.",
		],
		parameters: Type.Object({
			agent: Type.String({
				description: "Agent name, e.g. poteto-agent or pstack-why. See the catalog in the tool description.",
			}),
			task: Type.String({
				description:
					"Self-contained brief: purpose, scope, constraints, and file pointers. No inlined source dumps.",
			}),
			cwd: Type.Optional(
				Type.String({ description: "Working directory. Defaults to the parent session's cwd." }),
			),
			model: Type.Optional(
				Type.String({ description: 'Model override as "provider/id". Default: inherit the parent model.' }),
			),
			thinkingLevel: Type.Optional(
				Type.String({ description: "off, minimal, low, medium, high, xhigh, or max." }),
			),
			async: Type.Optional(
				Type.Boolean({
					description: "Default true. Set false to block and return the output in this turn.",
				}),
			),
		}),
		async execute(_id, params, signal, onUpdate, ctx) {
			agents = loadAgents(ctx.cwd ?? process.cwd());
			const def = agents.get(params.agent);
			if (!def) {
				const known = uniqueAgents(agents)
					.map((a) => a.name)
					.join(", ");
				return {
					content: [
						{
							type: "text",
							text: `Unknown agent "${params.agent}". Known agents: ${known}`,
						},
					],
					isError: true,
				};
			}

			if (depth() >= maxDepth()) {
				return {
					content: [
						{
							type: "text",
							text: `Delegate nesting limit reached (depth ${depth()}, max ${maxDepth()}). Do this work yourself.`,
						},
					],
					isError: true,
				};
			}
			if (!params.task.trim()) {
				return {
					content: [{ type: "text", text: "task must be a non-empty string." }],
					isError: true,
				};
			}

			const run = launch({
				def,
				task: params.task,
				cwd: params.cwd ?? ctx.cwd ?? process.cwd(),
				model: params.model,
				thinkingLevel: params.thinkingLevel,
				tools: childToolNames(def),
				depth: depth(),
				maxDepth: maxDepth(),
				onFinish: (finished) => {
					notify(summary(finished));
				},
			});

			if (params.async === false) {
				const settled = await waitFor([run.runId], DEFAULT_WAIT_MS, signal, onUpdate);
				return {
					content: [{ type: "text", text: settled }],
					details: { runId: run.runId, agent: run.agent, status: run.status },
				};
			}

			return {
				content: [
					{
						type: "text",
						text: `Started ${def.name} as ${run.runId} (${def.readonly ? "read-only" : "may write"}). The result arrives as a follow-up message.`,
					},
				],
				details: { runId: run.runId, agent: run.agent, status: run.status },
			};
		},
	});

	pi.registerTool({
		name: "poteto_delegate_wait",
		label: "Wait For Delegate",
		description:
			"Block until one or all running poteto_delegate runs finish, then return their output. Omit runId to wait for whichever finishes first.",
		parameters: Type.Object({
			runId: Type.Optional(Type.String({ description: "Wait for this run. Omit to wait for any." })),
			all: Type.Optional(Type.Boolean({ description: "Wait for every run that is active now." })),
			timeoutMs: Type.Optional(
				Type.Number({ description: `Max wait in ms. Default ${DEFAULT_WAIT_MS}.` }),
			),
		}),
		async execute(_id, params, signal, onUpdate) {
			const ids = params.runId
				? [params.runId]
				: [...runs.values()].filter((r) => r.status === "running").map((r) => r.runId);
			if (ids.length === 0) {
				return {
					content: [{ type: "text", text: "No matching runs are active." }],
				};
			}
			const text = await waitFor(
				ids,
				params.timeoutMs ?? DEFAULT_WAIT_MS,
				signal,
				onUpdate,
				params.all === true,
			);
			return { content: [{ type: "text", text }] };
		},
	});

	pi.registerTool({
		name: "poteto_delegate_cancel",
		label: "Cancel Delegate",
		description: "Cancel a running poteto_delegate run by runId.",
		parameters: Type.Object({
			runId: Type.String({ description: "The runId returned by poteto_delegate." }),
		}),
		async execute(_id, params) {
			const ok = cancel(params.runId);
			return {
				content: [
					{
						type: "text",
						text: ok ? `Cancelled ${params.runId}.` : `No running run ${params.runId}.`,
					},
				],
			};
		},
	});

	pi.registerCommand("poteto-agents", {
		description: "List the poteto agents this extension can launch.",
		handler: async (_args, ctx) => {
			agents = loadAgents(ctx.cwd ?? process.cwd());
			const all = uniqueAgents(agents);
			const advertised = all.filter((a) => a.advertise);
			ctx.ui.notify(
				`${all.length} agents (${advertised.length} advertised)\n${catalog(all, false)}`,
				"info",
			);
		},
	});

	async function waitFor(
		ids: string[],
		timeoutMs: number,
		signal: AbortSignal | undefined,
		onUpdate: ((u: { content: { type: "text"; text: string }[] }) => void) | undefined,
		all = false,
	): Promise<string> {
		const deadline = Date.now() + timeoutMs;
		const pending = new Set(ids);

		for (;;) {
			for (const id of [...pending]) {
				const run = runs.get(id);
				if (run && run.status !== "running") pending.delete(id);
			}

			if (pending.size === 0 || !all) {
				const finished = ids
					.filter((id) => {
						const run = runs.get(id);
						return run && run.status !== "running";
					})
					.map((id) => runs.get(id) as Run);
				if (finished.length > 0) {
					return finished.map(summary).join("\n\n---\n\n");
				}
			} else if (pending.size === 0) {
				return ids.map((id) => summary(runs.get(id) as Run)).join("\n\n---\n\n");
			}

			if (Date.now() > deadline) {
				const live = ids
					.filter((id) => runs.get(id)?.status === "running")
					.map((id) => id)
					.join(", ");
				return `Timed out after ${Math.round(timeoutMs / 1000)}s. Still running: ${live}. The result will arrive as a follow-up message.`;
			}
			if (signal?.aborted) return "Wait aborted.";

			onUpdate?.({
				content: [{ type: "text", text: `Waiting on ${pending.size} run(s)\u2026` }],
			});
			await new Promise((resolve) => setTimeout(resolve, 250));
		}
	}
}
