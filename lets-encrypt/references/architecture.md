# Let's Encrypt architecture: clients, challenges, rate limits, automation

Deep reference covering ACME client comparison, challenge mechanics and timing, rate-limit tables, certificate lifetimes and profiles, certbot and acme.sh commands, built-in ACME server configs (Caddy, Traefik), renewal hooks, common issue fixes, and the production checklist.

## ACME client comparison

| Client | Language | Best for | Notes |
|---|---|---|---|
| certbot | Python | Standard Linux servers, nginx, Apache | Official EFF client; most documentation; DNS plugins per provider |
| acme.sh | Bash | Scriptable workflows, 150+ DNS providers, non-root install | No Python dependency; very broad DNS support |
| Caddy | Go | Servers running Caddy | Fully built-in; zero config for simple cases |
| Traefik | Go | Container environments using Traefik | Built-in; configured in traefik.yml |
| LEGO | Go | Go projects, CI pipelines | Library-embeddable |
| step CLI | Go | Internal CAs, `step-ca` integration | Works with Let's Encrypt and private ACME CAs |

## Challenge mechanics

### HTTP-01

Let's Encrypt places a token at a URL the requester must serve:

```
http://<domain>/.well-known/acme-challenge/<token>
```

The value at that URL must be the token followed by a period and the account key thumbprint. certbot and acme.sh handle this automatically. Constraints:
- Port 80 must be reachable from Let's Encrypt's validation servers (multiple vantage points globally).
- Does not support wildcards.
- An HTTPS redirect on port 80 must NOT intercept the `/.well-known/acme-challenge/` path before serving the token.

nginx config pattern that serves the challenge before redirecting:

```nginx
server {
    listen 80;
    server_name example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

### DNS-01

Let's Encrypt asks the requester to publish a TXT record:

```
_acme-challenge.<domain>  TXT  <token-value>
```

Let's Encrypt validates from multiple DNS resolvers. Propagation must complete before they check. Constraints:
- Requires DNS API access (automation) or manual TXT record creation.
- Required for wildcards (`*.example.com`).
- Works even when port 80 or 443 is not reachable.
- Propagation can take 30-120 s depending on the DNS provider and TTL.

Check propagation:

```bash
dig TXT _acme-challenge.example.com @8.8.8.8
dig TXT _acme-challenge.example.com @1.1.1.1
```

### TLS-ALPN-01

Let's Encrypt initiates a TLS handshake on port 443 using the `acme-tls/1` ALPN protocol. The server must respond with a self-signed certificate containing a special `acmeValidation` extension. Less commonly used; requires port 443 and a server that supports the ALPN protocol extension.

## Certificate lifetimes and profiles

| Profile | Lifetime | Typical renewal point | Available |
|---|---|---|---|
| Default (90-day) | 90 days | ~60 days (two-thirds) | Always |
| Short-lived (6-day) | 6 days | ~4 days | March 2025 |
| 45-day opt-in | 45 days | ~30 days | May 2026 |

**90-day default**: certbot and acme.sh renew at the two-thirds mark (approximately 60 days). This gives a 30-day window to resolve renewal failures before the cert expires.

**6-day short-lived**: intended for fully automated, high-assurance environments. Eliminates the practical need for OCSP (certificate expires before a revocation signal could propagate and be acted upon). Any renewal failure must be resolved within ~2 days. Do not use without thoroughly tested, monitored automation.

**45-day opt-in**: a middle ground available from May 2026. Renewal frequency (every ~30 days) is more comfortable than 6-day but with a smaller exposure window than 90-day.

## certbot

### Installation

```bash
# Ubuntu/Debian via snap (recommended; always current)
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# Ubuntu/Debian via apt
sudo apt install certbot python3-certbot-nginx

# macOS
brew install certbot

# pip (any platform)
pip install certbot certbot-nginx certbot-apache
```

### Obtaining certificates

```bash
# nginx: modifies nginx config automatically
sudo certbot --nginx -d example.com -d www.example.com

# Apache: modifies Apache config automatically
sudo certbot --apache -d example.com -d www.example.com

# Standalone: runs a temporary HTTP server on port 80
# Use when nginx or Apache is not currently running
sudo certbot certonly --standalone -d example.com

# Webroot: places challenge files in an existing document root
sudo certbot certonly --webroot -w /var/www/html -d example.com -d www.example.com

# DNS-01 wildcard via Cloudflare plugin
sudo certbot certonly --dns-cloudflare \
    --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
    -d example.com \
    -d "*.example.com"
```

### Certificate file locations

certbot stores certificates in `/etc/letsencrypt/live/<domain>/`:

```
/etc/letsencrypt/live/example.com/
  cert.pem        -> certificate only (do not use this for nginx or Apache)
  chain.pem       -> intermediate chain only
  fullchain.pem   -> cert.pem + chain.pem (use this for most servers)
  privkey.pem     -> private key (readable by root only)
```

nginx TLS config:

```nginx
ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
```

### DNS-01 plugins

certbot has provider-specific plugins installable via pip:

| Plugin | Provider |
|---|---|
| `certbot-dns-cloudflare` | Cloudflare |
| `certbot-dns-route53` | AWS Route 53 |
| `certbot-dns-google` | Google Cloud DNS |
| `certbot-dns-azure` | Azure DNS |
| `certbot-dns-digitalocean` | DigitalOcean |
| `certbot-dns-ovh` | OVH |

Cloudflare credentials file:

```bash
pip install certbot-dns-cloudflare

mkdir -p ~/.secrets/certbot
cat > ~/.secrets/certbot/cloudflare.ini << 'EOF'
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
EOF
chmod 600 ~/.secrets/certbot/cloudflare.ini

certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials ~/.secrets/certbot/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 60 \
    -d example.com \
    -d "*.example.com"
```

The credentials file contains a secret; see `secrets-hygiene` for storage guidance.

### Renewal

```bash
# Dry run: test renewal path without issuing
sudo certbot renew --dry-run

# Force renewal even if the cert is not near expiry
sudo certbot renew --force-renewal

# Renew a specific certificate only
sudo certbot renew --cert-name example.com

# Check the systemd renewal timer
sudo systemctl status snap.certbot.renew.timer

# Cron fallback (if not using snap)
# /etc/cron.d/certbot or root crontab:
0 0,12 * * * root certbot renew --quiet
```

### Renewal hooks

Hooks run at specific lifecycle points. Place scripts in the hook directories or reference them in the renewal config.

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
# Runs after every successful renewal
#!/bin/bash
systemctl reload nginx
```

```bash
# /etc/letsencrypt/renewal-hooks/pre/stop-haproxy.sh
#!/bin/bash
systemctl stop haproxy

# /etc/letsencrypt/renewal-hooks/post/start-haproxy.sh
#!/bin/bash
systemctl start haproxy
```

Or specify inline in `/etc/letsencrypt/renewal/example.com.conf`:

```ini
[renewalparams]
deploy_hook = systemctl reload nginx
```

Hook directory summary:

| Directory | When it runs |
|---|---|
| `renewal-hooks/pre/` | Before any renewal attempt (even if certificate is not due) |
| `renewal-hooks/deploy/` | After each successful renewal |
| `renewal-hooks/post/` | After all renewal attempts complete (success or failure) |

## acme.sh

Pure Bash ACME client. Supports 150+ DNS providers; no Python dependency; installs without root.

```bash
# Install (adds a cron entry automatically)
curl https://get.acme.sh | sh -s email=admin@example.com

# Issue via HTTP-01 (webroot mode)
acme.sh --issue -d example.com -w /var/www/html

# Issue via HTTP-01 (standalone; requires port 80 free)
acme.sh --issue -d example.com --standalone

# Issue wildcard via DNS-01 (Cloudflare example)
export CF_Token="your-cloudflare-api-token"
export CF_Account_ID="your-account-id"
acme.sh --issue -d example.com -d "*.example.com" --dns dns_cf

# Install certificate to nginx paths with reload command
acme.sh --install-cert -d example.com \
    --cert-file      /etc/nginx/ssl/cert.pem \
    --key-file       /etc/nginx/ssl/privkey.pem \
    --fullchain-file /etc/nginx/ssl/fullchain.pem \
    --reloadcmd      "systemctl reload nginx"

# List all managed certificates
acme.sh --list

# Force renew
acme.sh --renew -d example.com --force

# Check auto-renewal cron entry
crontab -l | grep acme
```

### Staging with acme.sh

```bash
# Issue from staging (separate rate limit pool)
acme.sh --issue -d example.com --standalone --staging

# Reissue from production after staging validates
acme.sh --issue -d example.com --standalone --server letsencrypt
```

## Built-in ACME servers

### Caddy

Caddy automatically obtains and renews Let's Encrypt certificates with no certbot required. TLS is on by default for any site with a public hostname.

```caddyfile
# Caddyfile: TLS is automatic
example.com {
    root * /var/www/html
    file_server
}

# Global email for account registration
{
    email admin@example.com
}
```

Point at an internal ACME CA instead:

```caddyfile
example.com {
    tls {
        ca https://step-ca.internal/acme/acme/directory
    }
}
```

### Traefik

```yaml
# traefik.yml
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@example.com
      storage: /letsencrypt/acme.json
      # HTTP-01 challenge
      httpChallenge:
        entryPoint: web
      # DNS-01 challenge (comment out httpChallenge above)
      # dnsChallenge:
      #   provider: cloudflare
      #   delayBeforeCheck: 30
```

```yaml
# Docker Compose labels on a service
labels:
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  - "traefik.http.routers.myapp.rule=Host(`example.com`)"
```

## Rate limits

Let's Encrypt applies sliding-window rate limits to prevent abuse.

| Limit | Value | Window |
|---|---|---|
| Certificates per registered domain | 50 | 7 days |
| Duplicate certificates (identical SAN set) | 5 | 7 days |
| Failed validations per account per hostname | 5 | 1 hour |
| New orders per account | 300 | 3 hours |
| New registrations per IP | 10 | 3 hours |

Key distinctions:
- The domain limit counts by registered domain (e.g. `example.com` includes all subdomains).
- The duplicate limit counts certificates with the exact same set of SANs.

### Avoiding rate limits

1. Use the staging endpoint during development and testing. Staging has separate, much higher limits.
2. Include all required SANs in one certificate rather than issuing separate certificates per subdomain.
3. Do not re-issue when the current certificate is still valid. Use `--force-renewal` sparingly.
4. Monitor issuance history: `https://crt.sh/?q=example.com` shows all certificates issued for a domain.

### Staging endpoint

```
https://acme-staging-v02.api.letsencrypt.org/directory
```

Staging certificates are signed by a staging CA that is not publicly trusted. Browsers show a warning; that is expected. Use staging to validate the full issuance pipeline without consuming production rate-limit quota.

### When you hit a rate limit

Let's Encrypt returns HTTP 429 or a JSON error body identifying the limit. The only resolution is to wait until the 7-day sliding window advances past the oldest certificate in the group. There is no manual reset.

Rate limit exception requests: `https://issuance-limit-requests.letsencrypt.org` (for legitimate high-volume operators).

Alternative CAs with separate rate limits (all ACME-compatible):
- ZeroSSL (free tier, separate limits)
- Google Trust Services (requires Google Cloud project)
- AWS Certificate Manager (ACM) for AWS-hosted workloads (no rate limits; free within ACM)

## Common issue fixes

### "Connection refused" on HTTP-01 challenge

1. Port 80 must be open in the firewall or cloud security group.
2. The web server must be listening on port 80.
3. The HTTPS redirect on port 80 must not intercept `/.well-known/acme-challenge/`. See the nginx pattern in the HTTP-01 section above.
4. If behind a load balancer, confirm the LB forwards `/.well-known/acme-challenge/` to the server running certbot, not a 404 or redirect.

### "DNS problem" on DNS-01 challenge

1. Check propagation from multiple resolvers:
   ```bash
   dig TXT _acme-challenge.example.com @8.8.8.8
   dig TXT _acme-challenge.example.com @1.1.1.1
   ```
2. Increase the propagation wait time for the DNS plugin (e.g. `--dns-cloudflare-propagation-seconds 120`).
3. Verify the DNS API token has `Zone:DNS:Edit` permission for the zone.
4. Check the zone TTL on the TXT record; a high TTL combined with stale resolver caches can delay validation.

### Certificate not renewed after expiry

1. Check certbot's timer: `systemctl status snap.certbot.renew.timer`
2. Check for a cron entry: `crontab -l | grep certbot` or `ls /etc/cron.d/certbot`
3. Read the log: `cat /var/log/letsencrypt/letsencrypt.log | tail -100`
4. List certificate status: `certbot certificates`
5. Confirm the deploy hook is reloading the server. If the hook fails, the server may be running but serving an old cert.

### CAA records blocking issuance

If your zone has CAA records, add Let's Encrypt:

```
example.com. CAA 0 issue "letsencrypt.org"
example.com. CAA 0 issuewild "letsencrypt.org"
```

Without these, any ACME CA not listed will be rejected by the DNS CAA check.

## Production checklist

- [ ] Test the full issuance flow with the staging endpoint before switching to production.
- [ ] Configure automatic renewal (certbot systemd timer or acme.sh cron).
- [ ] Set up a deploy/reload hook that signals the web server after successful renewal.
- [ ] Monitor certificate expiry independently (external monitoring tool, not just certbot logs).
- [ ] Add CAA DNS records permitting `letsencrypt.org`.
- [ ] Configure OCSP stapling in the web server (reduces client latency on TLS handshake).
- [ ] Test the final HTTPS configuration: `https://www.ssllabs.com/ssltest/`
- [ ] Set up alerting for renewal failures (email, PagerDuty, or equivalent).
- [ ] Store DNS API tokens and ACME account keys outside version control (see `secrets-hygiene`).
- [ ] If using 6-day certificates, confirm automated renewal succeeds end-to-end in staging first.
