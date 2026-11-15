---
name: review-compliance
description: >-
  Audits a codebase for legal exposure and distributor rules (App Store,
  Google Play, Steam, websites, and other stores). Use when the user runs
  /review-compliance or asks for a compliance, policy, terms-of-service,
  store-review, or legal-risk audit. Asks which distributor applies when the
  code does not make that clear. Classifies each finding as Critical/Mandatory,
  needs attention, low risk, or best practices.
disable-model-invocation: true
metadata:
  model: claude-opus-5-5-xhigh
---

# review-compliance

Read-only audit of this repo against legal risk and the rules of the distributors the product actually ships on. The report is a triage for a person. It is not a legal opinion, a store approval, or a substitute for counsel.

Do not edit files, open a submission, or "fix" findings while auditing. If the user later asks for a fix, that is a separate task, and anything labeled Critical/Mandatory still needs a person to confirm the rule before code changes that exist to satisfy a regulator or a store.

## Model

Run the audit on Claude Opus 5.5 at xhigh effort (`claude-opus-5-5-xhigh`). A skill cannot pin a model. The pin is the read-only subagent `compliance-auditor` in `.cursor/agents/compliance-auditor.md`.

1. Launch `compliance-auditor` on this repo.
2. Do not pass a model on that launch. A named model overrides the pin.
3. If that subagent cannot be launched, run this skill yourself and say at the top of the report that it did not run on `claude-opus-5-5-xhigh`.

## Ask which distributor

If a distributor is not specific use or clear in the code, ask.

A distributor is clear only when a project file, manifest, store config, or shipping doc names it. One SDK import, a comment, or a copied sample is not enough.

- Audit every distributor that is clear.
- Ask before scoring rules for one that is only hinted at. Name the files that made you unsure.
- Use the question tool when you have one. Otherwise ask in the report and stop the platform-specific labels for that distributor.
- Still report behavior you can see (accounts, location, payments, children, tracking, user content). Mark those store rules as not applied until the person answers.

## Classify

Use the user's labels verbatim and no others:

> Classify into Critical/Mandatory: legal or banned from platform level repercussions, needs attention: leaning towards being against ToS but not explicitly bad, low risk: some thing that are less serious but if they keep going in a bad direction could be critical, & best practices: anything minor/cosmetic that goes against tradition for the platform or code language or framework.

Spell the four labels exactly: `Critical/Mandatory`, `needs attention`, `low risk`, `best practices`.

- `Critical/Mandatory` only when a current public rule, statute, or ban you opened matches the code, and the consequence is legal liability or removal from that platform. Memory of a guideline number is not a match.
- `needs attention` when the code leans toward a violation the text does not clearly forbid, or you could not open the current policy.
- `low risk` when the issue is smaller and becomes serious if the same pattern keeps spreading.
- `best practices` when the gap is minor, cosmetic, or a tradition of that platform, language, or framework.

One finding, one label. Do not invent a fifth bucket.

## How to check a rule

1. Read [reference.md](reference.md) and detect distributors before searching for violations.
2. Search the repo for the signals in that file. Record `path:line` for every finding.
3. Open the current policy page for that distributor. Cite the page URL and the heading you used. Paraphrase the rule in one sentence. Do not paste the policy.
4. If the page will not open, do not use `Critical/Mandatory` for that item. Use `needs attention` and say the policy was not verified.
5. Do not put secrets, tokens, or coordinates in the report. Name the file and the kind of value.

## Report

```markdown
# Compliance audit

Model: claude-opus-5-5-xhigh | or the fallback note
Scope: <paths or whole repo>
Distributors: <name — evidence path> or Unclear
Not applied yet: <rules skipped because you asked>

## Questions
<only if a distributor is not specific use or clear in the code>

## Critical/Mandatory
### <short title>
- Where: `path:line`
- Seen: <what the code does>
- Rule: <url> — <heading> — <one-sentence paraphrase>
- Why this label: <legal or platform-ban consequence>
- Needs a person: <what they must confirm>

## needs attention
### <short title>
- Where: `path:line`
- Seen: ...
- Rule: <url and heading, or "policy not opened">
- Why this label: <leans against the terms; the text does not clearly forbid it>

## low risk
### <short title>
- Where: `path:line`
- Seen: ...
- Why this label: <smaller now; what spread would make it serious>

## best practices
### <short title>
- Where: `path:line`
- Tradition: <platform, language, or framework>
- Seen: ...

## Clear
<areas you checked and did not flag, with the files>
```

Omit an empty section's findings and write `None` under that heading. Do not claim the product is compliant.

Format examples: [examples.md](examples.md). Detection and per-store checks: [reference.md](reference.md).
