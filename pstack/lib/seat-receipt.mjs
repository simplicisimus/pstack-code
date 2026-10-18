#!/usr/bin/env node
// Reads the JSONL a Codex or Grok seat printed, writes Grok's answer file and the seat's receipt,
// and prints status=, reported_model=, model_check= and error= lines for pstack-seat.
//
//   seat-receipt.mjs --cli codex|grok --events FILE --answer FILE --receipt FILE --model M --effort E
//     --mode review|write --exit N --elapsed SECONDS --deadline-hit 0|1 [--note "note=a note=b"] [--log FILE]
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) {
	if (!argv[i].startsWith("--") || i + 1 >= argv.length) {
		process.stderr.write(`seat-receipt: bad arguments near ${argv[i]}\n`);
		process.exit(2);
	}
	args[argv[i].slice(2)] = argv[i + 1];
}

function events(path) {
	if (!path || !existsSync(path)) return [];
	const parsed = [];
	for (const line of readFileSync(path, "utf8").split("\n")) {
		if (!line.trim()) continue;
		try {
			const event = JSON.parse(line);
			if (event && typeof event === "object") parsed.push(event);
		} catch {}
	}
	return parsed;
}

const count = (value) => (typeof value === "number" && Number.isFinite(value) ? value : null);
const text = (value) => (typeof value === "string" && value.length > 0 ? value : null);

function usage(raw) {
	if (!raw || typeof raw !== "object") return null;
	return {
		input: count(raw.input_tokens),
		cached_input: count(raw.cached_input_tokens ?? raw.cache_read_input_tokens),
		output: count(raw.output_tokens),
		reasoning: count(raw.reasoning_output_tokens ?? raw.reasoning_tokens),
	};
}

// Grok answers a rolling name with a build of it, for example grok-4.7 with grok-4.7-build.
const sameModel = (requested, reported) => reported === requested || reported.startsWith(`${requested}-`);

function codex(list) {
	const found = { reported: null, usage: null, cost: null, session: null, error: null, failed: false };
	for (const event of list) {
		if (event.type === "thread.started") found.session = text(event.thread_id) ?? found.session;
		if (event.type === "turn.completed") found.usage = usage(event.usage) ?? found.usage;
		if (event.type === "turn.failed") {
			found.failed = true;
			found.error = text(event.error?.message) ?? "codex reported a failed turn";
		}
		// Codex also prints error events it recovers from, such as a dropped stream it retried.
		if (event.type === "error" && !found.error) found.error = text(event.message);
	}
	return found;
}

function grok(list, answerPath) {
	const found = { reported: null, usage: null, cost: null, session: null, error: null, failed: true };
	const result = list.filter((event) => event.type === "result").at(-1);
	if (!result) {
		found.error = "grok printed no result event";
		return found;
	}
	found.session = text(result.session_id);
	found.usage = usage(result.usage);
	found.cost = count(result.total_cost_usd);
	const served = Object.keys(result.modelUsage ?? {});
	found.reported = served.find((model) => sameModel(args.model, model)) ?? served[0] ?? null;
	if (result.is_error || result.subtype !== "success") {
		const errors = Array.isArray(result.errors) ? result.errors.filter(text) : [];
		found.error = errors.join(" ") || text(result.error) || text(result.error?.message) || text(result.result)
			|| `grok reported ${result.subtype ?? "an error"}`;
		return found;
	}
	const answer = text(result.result);
	if (answer === null) {
		found.error = "grok's result event has no text";
		return found;
	}
	writeFileSync(answerPath, answer.endsWith("\n") ? answer : `${answer}\n`);
	found.failed = false;
	return found;
}

const list = events(args.events);
const found = args.cli === "grok" ? grok(list, args.answer) : codex(list);
const bytes = existsSync(args.answer) ? statSync(args.answer).size : 0;
const exit = Number(args.exit);

let status = "complete";
if (args["deadline-hit"] === "1") status = "deadline";
else if (exit !== 0 || bytes === 0 || found.failed) status = "failed";

let check = "not-reported";
if (found.reported) check = sameModel(args.model, found.reported) ? "match" : "mismatch";

const notes = (args.note ?? "").split(/\s+/).filter(Boolean).map((note) => note.replace(/^note=/, ""));
if (check === "mismatch") notes.push("model-mismatch");
const error = status !== "complete" && found.error ? found.error.replace(/\s+/g, " ").trim().slice(0, 300) : null;

const receipt = {
	schema: 1,
	cli: args.cli,
	model: args.model,
	reported_model: found.reported,
	model_check: check,
	effort: args.effort || "default",
	mode: args.mode,
	status,
	exit,
	elapsed_s: Number(args.elapsed),
	answer: args.answer,
	bytes,
	usage: found.usage,
	cost_usd: found.cost,
	session_id: found.session,
	error,
	notes,
	events: args.events,
	log: args.log ?? null,
};
writeFileSync(args.receipt, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });

process.stdout.write(`status=${status}\n`);
process.stdout.write(`reported_model=${found.reported ?? ""}\n`);
process.stdout.write(`model_check=${check}\n`);
process.stdout.write(`error=${error ?? ""}\n`);
