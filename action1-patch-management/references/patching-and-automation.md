# Patching and automation

## Automation policies

The platform's purpose is autonomous patching: policy-based automations remove the manual touch from routine patch work. A policy controls:

- **Approval workflow:** which patches deploy automatically and which need an approve/decline decision (for example auto-approve OS security updates, hold feature updates for review).
- **Scheduling:** when the policy runs (daily, weekly, on patch-release).
- **Maintenance windows:** the time bands in which deployment and reboots are permitted, so patching happens off-hours and never mid-business-day.
- **Reboot control:** whether, when, and how to reboot after a patch, with user notification options. Uncoordinated reboots are the most common patch-deployment incident, so set this explicitly rather than leaving it to default.

## Update rings

Stage deployment risk with update rings. The ring system uses **time-based progression**: a ring deploys patches that were "first successfully deployed X days ago" on the prior ring. So a patch lands on a test ring first, and only after it has survived X days there does it progress to the next ring and eventually production. This is the controlled-blast-radius pattern: a bad patch is caught on the test ring before it reaches the estate.

A typical ring layout:

1. **Test ring:** IT and pilot machines, deploys immediately.
2. **Early ring:** a broader but non-critical population, deploys after the patch has been stable on test for N days.
3. **Production ring:** the bulk of the estate, deploys after the early ring is clean.

## Third-party application patching

Action1 patches third-party applications, not just the OS, from a software repository of pre-configured packages (browsers, runtimes, productivity and utility software). Third-party apps are where a large share of the actually-exploited surface lives, so they belong in the same automation policies and rings as OS patches, not as an afterthought. The repository handles package sourcing and version tracking so a third-party update flows through the same approval and scheduling controls.

## Software deployment

Beyond patching, the software repository supports deploying applications to endpoints (install, update, remove), driven by the same policy and ring mechanics. This makes Action1 a software-distribution tool as well as a patch tool, useful for standardising a baseline application set across the estate.

## Relationship to the VM programme

These mechanics decide *how* a patch reaches the estate safely. *What* to patch first, and the SLA it must meet, is the vulnerability-management programme's decision (KEV/EPSS/CVSS, asset criticality, the SLA matrix); see `vulnerability-management`. Action1 is the "patch" remediation option that programme calls for, and the automation here is what makes that remediation reliable and staged rather than risky and manual.
