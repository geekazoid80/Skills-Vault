# WAAP scope and WAF operations

WAAP (web application and API protection) is the WAF plus the traffic-shaping controls that ride alongside it: layer 7 DDoS mitigation, bot management, rate limiting, and API protection. This reference also covers deployment models and the monitoring and logging that make a WAF a source of security telemetry rather than a silent proxy.

## What WAAP adds to a WAF

The core WAF is the signature and anomaly engine that inspects each request for OWASP Top 10 attacks. WAAP wraps that engine with controls that shape traffic on the same request path:

- **Layer 7 DDoS mitigation** absorbs application-layer floods.
- **Bot management** distinguishes good, neutral, and bad automation and treats each accordingly.
- **Rate limiting** caps request rates per client to blunt abuse and volumetric attacks.
- **API protection** applies schema validation, per-endpoint limits, and token checks to the API surface specifically.

Rate limiting and challenges (CAPTCHA, JavaScript challenges) are the shared mechanism that connects bot defence and layer 7 DDoS: both lean on the same tools to raise the cost of automated abuse.

## Layer 7 DDoS mitigation

Application-layer (layer 7) DDoS is distinct from volumetric (layer 3/4) attacks. Network-layer volumetric DDoS is the domain of `network-detection-response`; the WAF handles the application-layer variety.

**Characteristics of a layer 7 DDoS:**

- Uses valid HTTP requests, which makes it much harder to separate from legitimate traffic than a raw packet flood.
- Exhausts backend resources (database connections, application CPU and memory) rather than saturating the link.
- Achieves impact at far lower volume than a layer 3/4 attack, because each request costs the backend more than it costs the attacker.

**WAF mitigations:**

- Rate limiting per IP, per session, or per geography.
- Geographic blocking (temporarily blocking whole regions while under attack from them).
- Challenging suspicious traffic with JavaScript or CAPTCHA challenges, which absorb automated capacity because bots cannot solve them cheaply.
- Connection limits per client.
- Request-size limits to blunt large-body attacks.
- Slow-request (Slowloris) mitigation through timeouts on slow headers and bodies.

## Bot management

Not all automation is hostile, so bot management is about classification and differentiated treatment, not blanket blocking.

| Category | Examples | Treatment |
|---|---|---|
| Good bots | Search engine crawlers, uptime and monitoring agents | Allow (often allowlisted) |
| Neutral bots | Developer tools, legitimate API clients | Usually allow |
| Bad bots (simple) | Scrapers with static user agents, mass scanners | Block |
| Bad bots (sophisticated) | Headless browsers, distributed and residential-proxy bots | Challenge, then block |
| Credential stuffing | Automated login attempts with stolen credentials | Block and alert |

**Detection signals:**

- User-agent analysis (known-bad strings, headless-browser signatures).
- IP reputation (datacentre ranges, Tor exit nodes, known-bad actors).
- Behavioural analysis (request rate, timing patterns, interaction signals).
- Browser fingerprinting via JavaScript.
- Challenge pass rate (how a client fares against CAPTCHA or JavaScript challenges).

Verify good bots rather than trusting the user-agent string alone, since it is trivially spoofed; reverse-DNS or published IP ranges give a stronger signal for allowlisting a crawler.

## Rate limiting

Rate limiting at the WAF layer is distinct from application-level rate limiting and sits in front of the backend, so it protects endpoints even when the application itself has no limiter.

**Typical targets:**

- **Login endpoints**: a low per-IP ceiling to blunt credential stuffing.
- **API endpoints**: per-authenticated-user or per-IP ceilings.
- **Registration**: a per-IP hourly cap to stop spam account creation.
- **Password reset**: a per-email cap to stop abuse.
- **Global threshold**: a per-IP requests-per-second ceiling as general layer 7 DDoS protection.

**Dimensions to key the limit on:** per IP, per authenticated user, per session token, or per geographic region.

**Response options when a limit is exceeded:** block (HTTP 429 Too Many Requests), challenge (CAPTCHA), throttle (deliberately slow responses), or log only (while still in monitoring mode).

## API protection

APIs are a distinct attack surface, and a WAF that only guards the web UI leaves them exposed. Modern WAAP platforms add API-specific controls:

- **Schema validation**: enforce the OpenAPI or Swagger schema and reject requests that do not conform. This is a positive model applied to the API contract.
- **Per-endpoint and per-key rate limits**: tighter, more granular limits than a global ceiling.
- **Token validation**: verify signed tokens (for example JWT signatures and claims) at the WAF layer before the request reaches the backend.
- **Sensitive-data detection**: detect PII or payment-card data in responses to catch data leakage.
- **Positive security model**: allowlist the documented API paths and block undocumented ones, so shadow and deprecated endpoints do not become an unmonitored way in.

## TLS and the request path

A WAF terminates TLS (or is given visibility into it) so it can inspect encrypted traffic. That has operational consequences worth stating:

- **Enforce a modern TLS floor** (TLS 1.2 or higher) across the applications behind the WAF.
- **Header injection**: the WAF can add security response headers such as HSTS to every response.
- **Backend trust**: the WAF re-encrypts or proxies clean traffic to the backend; configure the backend to trust and accept only the WAF as its front door where possible.
- **Mutual TLS (mTLS)**: require client certificates for API-to-API traffic where the threat model calls for it.

## Deployment models

Where the WAF sits in the request path is driven by the fact that it must see plaintext HTTP, and it trades off blocking capability against availability risk.

- **Inline gateway.** All traffic passes through the WAF, which can therefore block effectively. It is a single point of failure unless deployed in high availability. Typical of cloud WAFs fronting an application.

  ```
  Internet -> [WAF] -> Application
  ```

- **Reverse proxy.** The WAF terminates TLS, inspects the request, and proxies clean traffic to the backend, often handling load balancing too. Common for appliance and software WAFs in front of application servers.

  ```
  Internet -> [WAF as reverse proxy] -> Application servers
  ```

- **Cloud and CDN edge.** The WAF is built into the platform's load balancer or CDN edge, where TLS already terminates, so traffic is inspected at the edge without separate routing. This adds the CDN's own scale to DDoS absorption.

- **Out-of-band / monitoring.** The WAF receives a copy of mirrored traffic. It cannot block, only detect and alert, so it is used during initial deployment to observe and tune rules before any enforcement is in the request path.

  ```
  Internet -> Application (traffic mirrored) -> [WAF monitoring]
  ```

Choose the model on traffic volume, availability requirements (an inline WAF needs HA), and whether the WAF should also carry load balancing or edge caching.

## Monitoring and logging

WAF logs are security telemetry, not just proxy access logs. Treat them as a first-class data source.

A blocked-request log entry typically carries the timestamp, client IP, request method and URI, user agent, the rule ID and message that fired, the matched data and location (for example `request_body.password`), the action taken, the response code, and the anomaly score. Those fields are what make tuning and investigation possible.

**Key analyses to run:**

- **Top blocked rule IDs**: the rules firing most are the first tuning candidates (either a real attack campaign or a false-positive source).
- **Top blocked source IPs**: separates attackers from misconfigured-but-legitimate clients.
- **Block rate over time**: trends reveal attack campaigns and false-positive spikes that follow an application deployment.
- **Blocked URLs**: which endpoints are being attacked, and which are generating false positives.

**SIEM integration.** Forward WAF logs to the SIEM (or the security data platform in use) so they can be correlated with application logs, authentication events, and threat intelligence. A WAF whose logs no one reads catches attacks silently and lets false-positive spikes go unnoticed; the log pipeline is part of the control, not an afterthought. SIEM investigation and detection engineering on that data belong to the SIEM and detection skills, not here.
