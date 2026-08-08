# DNSSEC chain of trust

## Overview

DNSSEC adds cryptographic signatures to DNS records, creating a chain of trust from the root zone down to individual domain records:

```
Root zone (.)
  -> Signs the .com TLD with the root KSK; a DS record at the root points to the .com KSK
       -> The .com TLD signs example.com NS records with the .com KSK
            -> A DS record at .com points to the example.com KSK
                 -> example.com signs its records with the ZSK
                      -> The KSK signs the DNSKEY RRset (ZSK plus KSK)
```

## Key types

**KSK (Key Signing Key):**

- Signs only the DNSKEY record set.
- Long-lived (typically 1 to 2 years).
- Higher key strength (2048-bit RSA or 256-bit ECDSA).
- The DS record derived from the KSK is published in the parent zone.
- KSK rollover requires a parent-zone DS record update.

**ZSK (Zone Signing Key):**

- Signs all other record sets in the zone.
- Shorter-lived (typically 90 days).
- Can be a smaller key for performance.
- ZSK rollover is fully automated (the prepublish method).

**CSK (Combined Signing Key):**

- A single key serving both KSK and ZSK roles.
- Simplifies key management (used by the BIND `default` policy and by Cloudflare).
- Trade-off: rolling it requires a DS update at the parent, like a KSK.

## DS record (Delegation Signer)

The DS record is the trust anchor linking parent to child:

- Published in the parent zone (for example, .com publishes the DS for example.com).
- Contains a hash of the child zone's KSK.
- Validators use the DS to verify the child's DNSKEY, then use the DNSKEY to verify RRSIG signatures.
- The DS record must be updated at the registrar or parent when the KSK is rolled.

## Validation process

1. The resolver has the trust anchor for the root zone (built in).
2. It queries the root for `.com` NS, gets RRSIG, and validates with the root DNSKEY.
3. It follows the DS record for `.com` and validates the `.com` DNSKEY.
4. It queries `.com` for `example.com` NS and validates with the `.com` DNSKEY.
5. It follows the DS record for `example.com` and validates the `example.com` DNSKEY.
6. It queries `example.com` for `www.example.com` A and validates the RRSIG with the ZSK.

## Algorithm recommendations

| Algorithm | Code | Recommendation |
|---|---|---|
| ECDSAP256SHA256 | 13 | Recommended (compact signatures, fast) |
| ECDSAP384SHA384 | 14 | High-security environments |
| ED25519 | 15 | Modern, very compact |
| RSASHA256 | 8 | Widely compatible, larger signatures |
| RSASHA1 | 5/7 | Deprecated; avoid |

## NSEC vs NSEC3

- **NSEC**: proves non-existence by listing the next existing name. Allows zone enumeration (walking).
- **NSEC3**: uses hashed owner names to prove non-existence, preventing zone walking. RFC 9276 recommends iterations=0 and salt-length=0.

## Rollover failure modes

DNSSEC failure is binary, not graceful: a broken chain makes the entire zone unresolvable for validating resolvers. The recurring causes:

- **DS desynchronisation**: the KSK was rolled but the parent DS record was not updated (or vice versa). The new DNSKEY cannot be validated against the old DS.
- **Premature key retirement**: a key was removed while signatures it produced were still cached by resolvers, leaving cached RRSIGs that no longer validate.
- **Expired signatures**: RRSIG records have an explicit expiry. If re-signing automation stalls, signatures expire and validation fails even with correct keys.
- **Algorithm rollover errors**: changing algorithm requires both old and new signatures present during the transition; skipping the dual-sign window breaks validation.

Mitigation: monitor KSK/ZSK validity windows, RRSIG expiry, and parent DS records continuously. Treat every rollover as a change-controlled operation with a verified pre-check (parent DS matches the active KSK) and a rollback plan.
