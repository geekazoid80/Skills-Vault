---
name: inventory-recency-join
description: "Use when reading, counting, or reporting a distribution of AGENT-REPORTED state across a fleet or estate: patch levels, antivirus or EDR engine versions, OS builds, agent or client versions, config-compliance status, backup last-run, certificate expiry, licence or seat usage, asset inventory. Trigger phrases include \"how many are out of date\", \"version spread\", \"N devices behind\", \"patch coverage\", \"compliance report\", \"who has not updated\", \"fleet inventory\", \"rollout status\", \"percent compliant\". ALSO fires on the SYMPTOMS of the failure: a long tail of old versions, a handful of stragglers, hosts that look unpatched, an inventory that disagrees with the vendor console, or a spread that seems to show auto-update is broken. Iron rule: a state distribution is not reportable until it is joined to last-check-in, because a dormant reporter is indistinguishable from a non-compliant one. NOT for a single named host (no distribution to skew) and NOT for state read live from the thing itself rather than from a check-in. Composes with anchored-pattern absence checks and paged-count truncation."
metadata:
  version: 1.0.0
---

# Inventory Recency Join

> **Skill marker**: When applying this skill, begin your reply with `[skill: inventory-recency-join]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Fleet state almost never comes from the fleet. It comes from a **store of the last thing each agent said**, and agents stop talking: laptops sleep, hosts are decommissioned without being unenrolled, VPN-only devices go months between check-ins, an agent breaks and never reports again. The store keeps serving that last statement forever, with no marker that it is old.

So a version column is not a distribution of *current state*. It is a distribution of *state as last reported*, and the two diverge exactly where the reporting is worst. That divergence is not random noise: dormant devices are frozen at whatever they ran when they went quiet, which is systematically older. **A stale reporter and a genuinely un-updated host look identical in the table, and there are usually more of the former.**

Core principle: **recency is not metadata about the reading, it is part of the reading.** Join it or do not report.

## The iron rule

**A state distribution is not reportable until every row carries its last-check-in, and the distribution is reported per recency band.**

Not "check freshness too". The recency column is a **required field of the output**, in the same way a count needs a denominator. A table without it is incomplete, not merely unpolished.

## The required output shape

Produce this, in this order. Do not produce a bare state histogram and add caveats in prose underneath.

1. **The denominator, split three ways.** Total in scope, how many returned state, and how many returned nothing. The non-responders are their own line.
2. **The state distribution per recency band.** Choose bands from the reporting cadence, not from habit. For a daily-checking agent, `<=7d / 8-30d / >30d` works; for a weekly one, widen it.
3. **The correlation verdict**, in one sentence, chosen from the three below.
4. **The action target**, which follows from the verdict and is frequently not the thing that prompted the question.

### Non-responders are a bucket, never a pass

A host that returned no state is **unknown**. It is not compliant, not clean, and not excluded. Fold it silently into "no data" and the compliance percentage becomes a statement about the devices healthy enough to answer, which is the population least likely to be the problem.

## Reading the join: three verdicts

Once state is banded by recency, the shape tells you which of three things you are looking at. Say which, explicitly.

| What the bands show | Verdict | What it means |
|---|---|---|
| Old state confined to stale reporters; fresh reporters are uniformly current | **Telemetry artefact** | The rollout is working. The apparent laggards are dormant, not behind. The real finding is the silence |
| Old state spread evenly across all recency bands, including fresh reporters | **Genuine gap** | Hosts are checking in and still not updating. This is a real compliance failure |
| Mixed, or too few fresh reporters to tell | **Undetermined** | Say so. Do not pick the flattering reading, and do not pick the alarming one |

The first verdict is the one that gets missed, because the un-joined table looks exactly like the second.

### The claim cannot outrun the reading

A host whose last check-in was 54 days ago supports a statement about **54 days ago**, and nothing about today. When quoting any figure, the age of the oldest contributing reading bounds the age of the whole claim. "12 hosts are on an old build" derived partly from two-month-old readings is not a present-tense sentence.

## Worked example

A fleet of 76 endpoints, asked "how many are behind on the security agent?".

**Un-joined, the shape that gets reported:**

| Engine version | Count |
|---|---|
| 1.1.26070.7 | 60 |
| 1.1.26060.3008 | 4 |
| 1.1.26050.11 | 3 |
| 1.1.26080.2 | 1 |

Read alone: eight hosts are behind, two of them badly, and auto-update looks unreliable. That reading is wrong, and it points the work at the wrong place.

**Joined to last-check-in:**

| Reported | n | Versions |
|---|---|---|
| Within 7 days | 45 | 44 current, 1 **newer** |
| 8 to 30 days | 19 | 16 current, 3 one behind |
| Over 30 days | 4 | all on the two oldest |
| No state returned | 8 | unknown |

Every host on an old version last checked in 12 to 54 days ago. Of the 45 that reported this week, **45 are current or newer**.

**Verdict: telemetry artefact.** Auto-update is demonstrably working, and this is stronger evidence than reading the update *setting* would have been, because it measures the outcome rather than the intent. **The action target moves**: the finding is not eight laggards to chase, it is twelve hosts (8 silent plus 4 stale) that are not reporting and therefore will not receive the next update either. Same data, different work.

Note the second row of the joined table. One host is on a **newer** version than the mode, which an "out of date" framing has no column for and quietly discards.

## What counts as a check-in

The join needs the timestamp of **the agent's last contact**, not of the record. These are different, and the wrong one silently defeats the whole check:

- **Use:** last check-in, last sync, last seen, last reported, heartbeat time, last successful inventory.
- **Do not use:** record created date, record modified date, the time you ran the query, or a "last updated" field the platform touches on its own writes. Any of these can be fresh for a host that has been silent for months.

If the store exposes no per-record check-in time at all, that is itself the finding: the inventory cannot support compliance claims, and saying so is more useful than producing a number that cannot be defended.

## Red flags

- About to write "N hosts are on an old version" from a table with no check-in column.
- A compliance percentage whose denominator excludes hosts that failed to report.
- Treating an empty, errored, or absent reading as compliant.
- Concluding that auto-update, a rollout, or a policy is broken from a version spread alone.
- Quoting an oldest-and-newest range without either value's check-in date.
- A "stragglers" list that nobody has checked is still in service.
- Bands chosen for neatness (30/60/90) rather than from the agent's actual reporting cadence.
- Reporting the same figure to a decision-maker that you would have reported before doing the join.

## Bottom line

Agent-reported state is a record of the last thing each host said, and quiet hosts are frozen at their last word. Join every state distribution to last-check-in, band it, and count the non-responders as their own bucket rather than as passes. Then say which of three things you are seeing: a telemetry artefact, a genuine gap, or not enough fresh data to tell. The join usually moves the work from the visible laggards to the invisible silent ones, which is the finding that was there all along.

Siblings: an anchored survey pattern under-reports and must never be read as absence; a paged count landing exactly on the page size is truncated. Same family, all three are measurements that look complete and are not.
