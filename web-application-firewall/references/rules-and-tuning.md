# WAF rules and tuning

Rule management, detection methods, the OWASP Core Rule Set, detection versus prevention modes, false-positive tuning, custom rules, and virtual patching. This is the day-to-day surface a WAF operator lives on.

## Rule types

A WAF policy is built from three kinds of rule, layered from most to least reusable.

- **Managed rules (vendor or community maintained).** Curated rule sets the vendor keeps up to date against emerging attacks. Most cloud and commercial WAFs ship managed rule groups derived from the OWASP Core Rule Set, plus vendor-specific groups for platform-specific threats (for example a rule group targeting a particular CMS or application framework). Managed rules are the baseline: enable them first, tune second.
- **Custom rules (operator authored).** Rules the team writes for its own application: block a specific attack pattern, allow a known-good client, enforce a positive model on a particular path. Custom rules carry local knowledge the managed set cannot have.
- **Exclusions and exceptions.** Not attack rules but scoped carve-outs that stop a managed or custom rule firing in a specific, documented context. These are the primary false-positive tool (see below).

Rules evaluate in order and typically combine conditions (URI, method, header, body, parameter, IP, geography, rate) with an action (allow, block, challenge, count/log, throttle).

## Detection methods

WAFs decide whether a request is malicious using several complementary methods.

- **Signature-based (most common).** Pattern matching against known attack strings, for example a regular expression matching `' OR 1=1--` for SQL injection. High performance and low false negatives for known attacks, but blind to novel or zero-day attacks whose pattern is not yet known.
- **Anomaly scoring.** Each matched rule contributes to a cumulative score, and the request is blocked only when the total crosses a configured threshold. This is far less brittle than block-on-any-match: a single borderline match does not block, but several together do. It is the model the OWASP Core Rule Set uses.
- **Behavioural analysis.** Establishes a baseline of normal traffic and flags deviations. Effective for account takeover, scraping, and layer 7 DDoS, but needs a learning period before enforcement is trustworthy.
- **Machine learning.** Trained models classify requests as malicious or benign and adapt to application-specific traffic over time, reducing false positives as they learn. Present in several commercial engines as an adjunct to, not a replacement for, signatures.

## The OWASP Core Rule Set (CRS)

The OWASP Core Rule Set is the industry-standard open-source WAF rule set, maintained by the OWASP project and historically paired with the ModSecurity engine. It is the foundation many commercial and cloud WAFs build their managed rules on, so understanding it transfers across products.

- **Broad coverage.** Thousands of rules covering the OWASP Top 10 and beyond (injection, cross-site scripting, local and remote file inclusion, protocol violations, and more).
- **Anomaly scoring.** Requests accumulate an anomaly score across matched rules; a threshold decides the block. Inbound and outbound scores are tracked separately.
- **Paranoia levels (PL1 to PL4).** The central tuning dial. Higher levels activate more rules, catching more attacks at the cost of more false positives.
  - **PL1**: basic protection, minimal false positives. The default starting point for most applications.
  - **PL2**: standard enterprise protection; some tuning expected.
  - **PL3**: high security; meaningful tuning required.
  - **PL4**: maximum security; significant tuning required and only justified for high-risk applications.
- **Current major version.** CRS 4.x is the current line; keep the rule set version current so coverage tracks new attack classes.

The paranoia level and the anomaly-score threshold are the two knobs that set the coverage-versus-false-positive trade-off. Raise the paranoia level for more coverage; raise the threshold to tolerate more borderline matches before blocking.

## Detection versus prevention (blocking) mode

A WAF operates in one of two enforcement postures, and the transition between them is the single most important operational discipline.

| Mode | Behaviour | Use case |
|---|---|---|
| Detection / monitor / count | Log and score violations, do not block | Initial deployment, testing new or raised-paranoia rules |
| Prevention / blocking | Reject requests that violate rules (typically HTTP 403) | Production enforcement once tuned |
| Challenge | Present a CAPTCHA or JavaScript challenge | Bot and suspected-automation traffic |
| Throttle | Rate-limit suspicious traffic rather than hard-block | Layer 7 DDoS and abusive clients |

**The rollout progression, every time:**

1. Enable the rules in detection mode across all traffic. Nothing is blocked yet.
2. Analyse the logs for false positives: which rules fire on legitimate requests, on which paths, from which known-good clients.
3. Tune: write targeted exclusions, adjust the paranoia level, or raise the anomaly threshold.
4. Enable blocking on the high-confidence rules first (the ones with clean, unambiguous matches).
5. Enable blocking on the remaining rules once tuning has settled.
6. Keep monitoring the false-positive rate, especially after each application deployment, since new application behaviour can trip previously quiet rules.

Turning on blocking for every rule on day one is the classic failure: it blocks legitimate users, generates a flood of complaints, and usually ends with the WAF being disabled entirely. Detection first is not optional.

## False-positive tuning

False positives (legitimate traffic blocked) are the primary operational challenge of running a WAF. The goal is to clear them without opening the vulnerability the rule exists to close.

**Common root causes:**

- Legitimate SQL-like or script-like text in form fields (a user searching for "O'Brien" contains an apostrophe; a user pasting code into a support form).
- Special characters in usernames, passwords, or content bodies.
- Security scanning and monitoring tools whose traffic trips attack rules.
- CMS and admin interfaces that legitimately issue complex queries.
- API payloads with unusual encoding or structure.

**The tuning loop:**

1. **Identify.** Review WAF logs for blocked requests from legitimate users: blocked authenticated sessions, blocked admin paths, blocked API calls from known-good clients. Address the highest-frequency false positives first.
2. **Analyse.** Determine which rule fired and why: the rule ID, the matched pattern, and the matched location (header, body, cookie, or specific parameter). Confirm the trigger pattern is genuinely present and genuinely benign in context.
3. **Exclude, narrowly.** Create a targeted exclusion scoped to the rule, the path, and the parameter, not a global disablement.

   ```
   # Good exclusion (targeted): rule, path, and parameter all scoped
   Exclude rule 942100 for path /api/search on parameter "query"

   # Bad exclusion (too broad): the rule is now off everywhere
   Disable rule 942100 globally
   ```

4. **Test.** Verify the exclusion resolves the false positive and that a real attack against the same rule on other paths still blocks.
5. **Document.** Record why each exclusion exists, so the audit trail explains every carve-out and a future reviewer can revisit it.

**Common legitimate exclusion patterns:**

- CMS and admin paths (for example `/admin`, or a platform's admin console) that legitimately use complex queries.
- Specific API endpoints and parameters known to carry benign payloads that resemble attacks.
- Trusted source IPs (corporate offices, monitoring and uptime services).
- Allowlisted user agents for known-good bots (search engine crawlers, monitoring agents), covered further in the WAAP reference.

The discipline throughout: prefer the narrowest exclusion that clears the false positive, and never reach for a global disable when a scoped exception will do.

## Custom rules and a positive security model

Beyond tuning managed rules, operators write custom rules to encode local knowledge:

- **Block a specific pattern** the application is known to be targeted with but the managed set does not cover.
- **Allow a known-good client** (a partner integration, an internal service) that would otherwise trip a rule.
- **Enforce a positive (allowlist) model** on a sensitive path: define what a valid request to that endpoint looks like and block everything else. A positive model is stronger than a negative (blocklist) model because it does not depend on enumerating every attack, but it requires knowing the legitimate surface precisely, so it fits well-defined APIs better than sprawling web UIs.

Order custom rules deliberately: allow rules for trusted traffic usually need to sit ahead of the broad managed blocks so a known-good client is not caught by a later rule.

## Virtual patching

Virtual patching is shielding a known application vulnerability with a WAF rule at runtime while the code fix is developed, tested, and deployed. It is a compensating control, not a remediation.

**When it earns its place:**

- A vulnerability is disclosed (a CVE in a component, a flaw found in testing) and exploit traffic is possible before the code fix can ship.
- The fix requires a release cycle, a vendor patch, or a change window that is not immediate.
- A legacy or third-party application cannot be modified quickly, or at all.

**How to apply it responsibly:**

- Write the rule as narrowly as possible: match the specific exploit pattern, path, and parameter, so it shields the vulnerability without blocking legitimate traffic to the same endpoint.
- Treat the virtual patch as time-boxed. Record the vulnerability it covers and the code fix that will retire it.
- Remove the virtual patch once the real fix is deployed and verified. A virtual patch left in place forever is technical debt that hides the fact the code was never fixed, and it can silently break when the application changes.

The iron rule: a virtual patch buys time for the fix, it is never the fix. Do not let a WAF rule become the reason the underlying vulnerability is never remediated.
