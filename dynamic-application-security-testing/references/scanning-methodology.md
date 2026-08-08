# Scanning methodology

This reference covers how a DAST scan actually works: the two phases every scanner runs, the difference between passive and active scanning and when each is safe, how to authenticate a scan and hold the session, how discovery (spidering and crawling) finds the surface, the extra handling APIs and single-page apps need, and how DAST relates to IAST. The methodology is scanner-agnostic; the mainstream tools (Burp Suite, OWASP ZAP, StackHawk) implement the same phases with different controls.

## The two phases

Every DAST scan runs discovery first, then attack, then reports.

**Discovery.** The scanner builds a map of the application's reachable surface. It follows links in returned HTML, parses forms and their inputs, imports any API schema it is given, and records every distinct endpoint, parameter, and request shape it can reach. What it fails to discover here, it cannot test later, so discovery quality sets the ceiling on coverage.

**Attack.** For each input the scanner found, it sends crafted payloads and analyses the response: injection strings for SQL, cross-site scripting and command injection; probes for authentication and authorisation weaknesses; checks for server-side request forgery; inspection of headers, cookies, and error pages. Findings carry the request and response as evidence.

**Report.** Findings are emitted with evidence, a severity, and a reproduction (the request/response pair). A machine-readable format (for example SARIF) lets a pipeline ingest the results.

Because DAST confirms a finding by seeing the running application respond, its findings carry a lower false-positive rate than a purely static analysis, but not zero: reflection that is never rendered, or an error string that is not really an injection point, still slips through and needs triage.

## Active versus passive scanning

The single most important safety distinction in DAST.

**Passive scanning** observes traffic without modifying any request. It reports what is visible in the responses the application already sends: missing or weak security headers, information disclosure in error pages, cookies without the secure or HttpOnly flags, cleartext transport, and server version leakage. It changes nothing, so it carries no risk of data modification or denial of service. Passive-only is the mode that is safe to run continuously, even against production, because it is indistinguishable from ordinary traffic in its effect.

**Active scanning** sends crafted attack payloads. It is how injection, cross-site scripting, command injection, and server-side request forgery are actually found, because those require provoking the application and observing the result. The cost is real risk: an active scan can write or delete data, exhaust resources and cause a denial of service, and trip rate limits or lockouts. It can submit forms, follow destructive links, and trigger side effects.

**The rule.** Active scanning runs only against an environment that is explicitly authorised for it, isolated from production, and populated with disposable data. Never point an active scan at production, and never at a shared environment holding real customer data, without explicit sign-off from whoever owns that environment. When in doubt, run passive first, understand the surface, then run active against a copy.

## Authenticated scanning and session handling

An unauthenticated scan reaches the login page and the handful of public routes in front of it, and nothing more. The bulk of an application's functionality (and therefore the bulk of its risk) sits behind authentication, so meaningful DAST authenticates.

**The common authentication shapes:**

- **Form-based login.** The scanner is given the login URL, the username and password field names, a set of credentials, and an indicator that distinguishes a logged-in response from a logged-out one (a string that only appears when authenticated, or its inverse). It submits the form, captures the resulting session cookie, and carries it through the scan.
- **Bearer or token authentication.** The scanner is given a token and told which header to place it in (commonly an `Authorization` header with a `Bearer` prefix). Common for API scanning where there is no login form.
- **OAuth or token-exchange flows.** The scanner is given a token endpoint and client credentials and performs the exchange to obtain an access token before scanning.

**Holding the session.** Authenticating once is not enough; the scan must stay authenticated for its whole run.

- Give the scanner a reliable logged-in indicator so it can detect when the session has dropped and re-authenticate automatically.
- Exclude the requests that would log the scanner out: the logout endpoint, session-invalidation links, and anything that rotates or revokes the token. Left unchecked, an active scan will eventually hit its own logout link and scan the rest of the app as an anonymous user, silently losing coverage.
- Where sessions are short-lived, configure re-authentication on expiry rather than assuming one login lasts the scan.

**Test-account discipline.** Use a dedicated account for DAST, not a real user or an admin:

- Give it realistic data so the scan exercises genuine data flows, not the empty state of a fresh account.
- Give it limited privilege, not administrative rights, so a stray destructive payload has a bounded blast radius.
- Use known credentials that can be rotated, and keep them in the environment's secret store rather than hard-coded in scan config.
- Run it against an isolated environment with its own database, separate from production data.

**Access-control testing.** With more than one test account at different privilege levels, DAST can compare what each role can reach and surface broken access control: a low-privilege account reaching a high-privilege function, or one user reaching another user's objects (insecure direct object reference). This is one of the higher-value things authenticated DAST does that an unauthenticated scan cannot.

## Spidering and crawling

Discovery for a traditional server-rendered application is a spider (also called a crawler): the scanner requests a page, extracts every link and form, follows them, and repeats until the surface is exhausted or a limit is hit. Good crawling depends on:

- **Seeding.** Start from the real entry points, and from an authenticated session so the crawler sees the pages that only exist after login.
- **Scope guards.** Constrain the crawl to the application under test (an allowlist of in-scope hosts and paths) so it does not wander onto third-party domains or unrelated services.
- **Depth and breadth limits.** Cap how far the crawl follows to keep the scan bounded, especially on a PR gate where time is short.

A crawler is only as good as what the application exposes as links and forms. That assumption breaks on modern front ends.

## API and single-page-app scanning

Two cases where naive crawling misses most of the surface.

**Single-page applications.** A single-page app renders in the browser from JavaScript and exposes almost none of its real surface as HTML links. The functionality lives in API calls the client makes after load. A link-following spider sees the initial shell and stops. Cover a single-page app by driving it with a browser-capable crawler that executes the JavaScript and observes the resulting API traffic, and, better, by scanning the underlying API directly from its schema (below). Treating the API as the real surface is usually more reliable than trying to crawl the rendered client.

**APIs.** Most modern applications are API-driven, and APIs must be covered explicitly rather than left to a crawler.

- **Schema-driven scanning is the preferred path.** Hand the scanner the API definition (OpenAPI/Swagger, a GraphQL schema, or a WSDL) and it generates test cases for every endpoint, method, and parameter automatically. This gives complete, deterministic coverage that does not depend on the scanner guessing endpoints.
- **GraphQL has a distinct attack surface** worth calling out: an exposed introspection endpoint that reveals the whole schema; deeply nested queries that cause denial of service; query batching that packs many operations into one request; and object-id arguments that enable insecure direct object reference.
- **OWASP publishes an API-specific top-ten** (broken object-level authorisation, broken authentication, broken object-property-level authorisation, unrestricted resource consumption, broken function-level authorisation, unrestricted access to sensitive business flows, server-side request forgery, security misconfiguration, improper inventory management, and unsafe consumption of upstream APIs). Object-level and function-level authorisation flaws dominate API risk and are exactly what multi-account authenticated scanning is positioned to find.

## What DAST covers well, and what it does not

DAST is strong on classes of flaw that manifest at runtime and weak on those that need to see intent or internal state.

- **Strong:** injection (high-confidence, because it provokes and observes the result), transport and cookie misconfiguration, security-header gaps, exposed endpoints and error pages, authentication and session weaknesses, and server-side request forgery.
- **Partial:** broken access control (good with multiple accounts and forced browsing, but it cannot know the intended authorisation model), and integrity or deserialisation issues (probeable but not always confirmable from outside).
- **Weak or blind:** insecure design (a logic flaw needs an understanding of intent that outside-in testing does not have), vulnerable third-party components (only partially fingerprinted from version leakage; dependency inventory is a software-composition-analysis job), and logging or monitoring failures (invisible from outside the application).

DAST and static analysis are complementary lenses, not substitutes: static analysis reads all code paths but reasons about theoretical reachability, while DAST reaches only what it can crawl but confirms real exploitability. A mature programme runs both.

## DAST versus IAST

Interactive Application Security Testing (IAST) instruments the application from the inside (an agent inside the runtime) and watches how a request flows through the code as the application is exercised. It sits between static analysis and DAST:

- **DAST is outside-in and black-box.** It needs no agent and no code, only a reachable running instance. It sees exactly what an external attacker sees, which makes its findings realistic but limits them to what is reachable from outside.
- **IAST is inside-out and instrumented.** Because it watches execution, it can pinpoint the vulnerable line, sharply reduce false positives, and see data flows a black-box scan cannot, but it needs an agent deployed in the runtime and only covers the code paths that get exercised (often driven by functional or DAST traffic).

They are not mutually exclusive: a common pattern runs DAST or functional tests to exercise the application while an IAST agent observes from within, combining realistic outside-in traffic with inside-out precision. Choose DAST when you cannot instrument the runtime or want a true attacker's-eye view; add IAST when you can deploy an agent and want lower false positives and line-level attribution.
