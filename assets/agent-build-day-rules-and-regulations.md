# Agent Build Day: Rules and Regulations (Lane 3)

**Event:** The Open Accelerator Agent Build Day
**Date:** Saturday, June 27, 2026, 9:30 AM to 6:00 PM
**Location:** The Open Accelerator, Boston, Fort Point
**Hosts:** Red Hat, IBM (IBM Ventures), and the Commonwealth of Massachusetts (Mass AI Hub)
**Your lane:** Lane 3, Most Innovative Use of Multiple Agents and Skills
**Contact:** hackathon@the-open-accelerator.com

This document covers the general rules plus everything specific to Lane 3. Use the Pre-Submission Checklist at the bottom as your final source of truth before commit freeze.

---

## 1. The deadline that matters

**4:00 PM is the hard stop: Build Window Closes and Commit Freeze.** Final commit must be in and repos tagged by then. Nothing after this counts.

> Note on times: the schedule header mentions a "six-hour build window opening at 11:00 AM," but the run of show lists the build window opening at 10:45 AM and closing at 4:00 PM. Treat 4:00 PM commit freeze as authoritative and plan backward from it. Leave buffer to tag the repo and run final validation before 4:00.

Other anchor times:
- **11:00 AM** Team formation and lane declaration. You register your lane and your repo URL here. Do not skip this.
- **3:00 PM** Midpoint check. Optional ADLC "evaluate" checkpoint and a reminder to capture metrics.
- **5:15 PM** Finalist demos (top submission per lane).
- **5:55 PM** Awards and close.

---

## 2. What Lane 3 asks you to build

Compose **multiple agents and multiple skills into a novel system.** The judges are looking for one or more of: multi-agent orchestration, agent-to-agent delegation, skill composition.

The framing they suggest: a natural fit is the LangChain Deep Agents SDK (MIT-licensed) with its four components, a planner, sub-agents, a virtual filesystem, and a detailed system prompt. You are not required to use it, but it signals what "good" looks like to them.

### Lane 3 Bar to Clear (the minimum to be eligible)

1. **At least two cooperating agents AND at least two skills.** Both counts matter. A multi-agent system with only one skill does not clear the bar. This is the most common Lane 3 trap, so confirm you have two genuine, separately-loaded skills.
2. **A clear delegation or composition mechanism.** It must be obvious how agents hand off to each other or how skills compose. Be ready to point at it explicitly.
3. **An ADLC worksheet plus a model-selection rationale across the agents.** Note "across the agents," meaning the rationale should cover which model each agent or sub-agent uses and why.

### Lane 3 idea seeds (for reference, not requirements)
- An orchestrator delegating to specialized sub-agents (research, synthesis, verification) with per-sub-agent model routing and a shared file-system workspace.
- A skill-composition system where one task cleanly activates several skills.
- Agent-to-agent delegation over MCP tools, with isolation enforced at the tool or sandbox level (for example E2B Firecracker microVMs).

---

## 3. Universal requirements (apply to all lanes, including yours)

These are non-negotiable regardless of lane.

- **Model-selection rationale, written.** Every submission includes a written rationale for which model handles which task, with at least a qualitative cost / latency / quality justification. A quantitative comparison is required "where feasible" and is rewarded in judging (see rubric). Hybrid local plus frontier architectures are explicitly encouraged.
- **Team size:** maximum 5 participants. Solo is supported.
- **Public repo** with README and an OSI-approved license.
- **Completed ADLC worksheet:** one page per phase across scope, design, build, evaluate, deploy, observe, iterate. With at least one evaluate/observe loop.

---

## 4. Definition of a shippable Skill (agentskills.io spec)

Judges grade skills against the agentskills.io spec, not on taste. Each skill is a directory that conforms to the spec:

- **`SKILL.md`** with valid YAML frontmatter plus a Markdown body.
- **`name`:** 1 to 64 characters, lowercase letters, numbers, and hyphens only, and it must match the directory name.
- **`description`:** 1 to 1,024 characters, stating both what the skill does and when to use it, including trigger keywords.
- **Progressive disclosure:** metadata (roughly 100 tokens) loads at startup; the body stays under 5,000 tokens / 500 lines; resources load on demand.
- **Optional directories used correctly:** `scripts/`, `references/`, `assets/`.
- **Validates** with `skills-ref validate ./my-skill`.
- **Distributed as an installable artifact:** public GitHub repo, README, OSI license.

Reminder for Lane 3: you need **two** of these, each validating cleanly.

---

## 5. Definition of a shippable Agent prototype

A working agent (an LLM in a loop with a harness) that:

- Completes its target task end-to-end on at least one realistic input.
- Loads at least one custom skill.
- Runs from a public repo with a README and setup instructions.
- Ships with a documented model-selection rationale (local vs. frontier, with cost / latency / quality justification).
- Includes a completed ADLC worksheet, one page per phase.

(The Lane 2 baseline-tag and before/after requirement does not apply to you in Lane 3.)

---

## 6. Judging rubric (80 points, four criteria)

| Points | Criterion | What they check |
|---|---|---|
| 25 | **Shippability and Spec Conformance** | Does it run? Do the skills validate against the agentskills.io spec? Public repo plus README plus license present. |
| 20 | **ADLC Discipline** | Evidence across all seven phases. Completed worksheet, with at least one evaluate/observe loop. |
| 20 | **Lane-Specific Merit (Lane 3)** | Novelty and soundness of the multi-agent orchestration. |
| 15 | **Skill Quality** | Per agentskills.io best practices: grounded in real expertise, a coherent unit of work, defaults not menus, gotchas section, output templates. |

**Key scoring rule on Skill Quality:** a skill that demonstrably raises the eval pass-rate over a no-skill baseline earns full marks. A skill that does not beat the baseline cannot earn full marks. In practice this means: build the with-skill vs. without-skill comparison and show the delta.

---

## 7. Evaluation method (how to produce the eval/observe evidence)

This is the method the judges expect for the ADLC evaluate loop and for the skill-quality delta:

1. Write 2 to 3 test cases in `evals/evals.json`.
2. Run them **with** the skill and **without** the skill.
3. Use specific, observable, countable assertions; mark each PASS or FAIL with evidence.
4. Aggregate into `benchmark.json` and read the delta.

---

## 8. Lane 3 award

- **Best Multi-Agent / Skill Composition.**
- Review with TOA and Red Hat agentic harness experts to define a future roadmap.
- Special TOA Agent prize pack.
- Hardware prize: Zeus Robot Car Kit.

---

## 9. Common failures to avoid

- Vague skill instructions.
- Too many options with no default.
- An over-long `SKILL.md` that blows the context budget.
- Skipping evaluation entirely.
- No model-selection rationale.
- Skill-security failures (unsandboxed `scripts/`, open egress, secrets in the repo).

---

## Pre-Submission Checklist (run this before the 4:00 PM commit freeze)

The build itself is the part you will not forget. These are the deliverables that are easy to lose track of and that the rubric grades directly. Walk this list before you freeze.

**Lane 3 eligibility**
- [ ] At least **two cooperating agents** are present and actually cooperate.
- [ ] At least **two skills** are present (not just two agents).
- [ ] The **delegation or composition mechanism** is identifiable and demoable.

**Skills (for each of your skills)**
- [ ] `SKILL.md` has valid YAML frontmatter and a Markdown body.
- [ ] `name` is lowercase/numbers/hyphens, 1 to 64 chars, and matches the directory name.
- [ ] `description` states what and when, includes trigger keywords, under 1,024 chars.
- [ ] Body is under 5,000 tokens / 500 lines; heavy content moved to `references/`, `scripts/`, or `assets/`.
- [ ] `skills-ref validate ./skill-name` passes for **each** skill.

**Agents**
- [ ] Each agent completes its task end-to-end on at least one realistic input.
- [ ] Each agent loads at least one custom skill.

**Documentation deliverables**
- [ ] **Model-selection rationale** written down: which model handles which task, per agent/sub-agent, with cost / latency / quality justification. Quantitative comparison included if feasible.
- [ ] **ADLC worksheet** complete: one page each for scope, design, build, evaluate, deploy, observe, iterate.
- [ ] At least **one evaluate/observe loop** documented (with vs. without skill, PASS/FAIL evidence, delta).
- [ ] `evals/evals.json` present with 2 to 3 test cases; results aggregated into `benchmark.json`.

**Repo and shippability**
- [ ] Public GitHub repo.
- [ ] README with setup instructions.
- [ ] OSI-approved license file.
- [ ] No secrets committed; `scripts/` egress reviewed.

**Logistics**
- [ ] Lane declared and repo URL registered at the 11:00 AM team formation step.
- [ ] Final commit pushed and **repo tagged** before 4:00 PM.
