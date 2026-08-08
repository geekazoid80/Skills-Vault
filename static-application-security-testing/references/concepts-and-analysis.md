# Concepts and analysis

This reference covers how SAST works under the hood: the parse-and-analyse pipeline, the rule engine types, taint and data-flow analysis, the source-sink-sanitiser model, how language and framework coverage varies, and what SAST structurally finds versus what it misses. It is the theory a request needs when it asks why a finding was raised, why one was missed, or how much to trust a clean result.

## From source to intermediate representation

A SAST tool does not read code the way a human does. It first parses the source (or disassembles the bytecode or binary) into an intermediate representation, typically an abstract syntax tree (AST) that captures the structure of every statement and expression. Richer engines build further representations on top: a control-flow graph that models how execution can move between statements, a call graph that links every call site to the functions it can reach, and a data-flow graph that tracks how values move between variables. The depth of these representations is what separates a shallow linter from a precise taint engine, and it is also what makes the precise engines slow.

Everything the tool can reason about is bounded by what it can parse. Code it cannot parse (an unsupported language, a generated file it skips, a macro or template it cannot expand, a dynamically constructed call it cannot resolve) is invisible to the analysis. A clean result over code the tool could not fully model is not the same as a clean result over code it understood.

## Rule engine types

SAST engines apply one or more analysis techniques, trading speed against precision:

- **Pattern matching (regex or token):** matches text or token patterns. Fast and simple, useful for coarse checks like a banned function name, but blind to context, so it both misses obfuscated variants and over-reports on lookalikes. Highest false-positive potential.
- **AST matching:** matches structural patterns in the syntax tree rather than raw text, so it understands that a call is a call regardless of formatting or intervening whitespace. More precise than regex, still local to the matched node, so it does not follow data across statements.
- **Semantic and control-flow analysis:** reasons about types, reachability, and how execution can arrive at a point. Used to infer variable types even in dynamically typed languages and to determine whether a suspect path is reachable at all, which is a primary lever for cutting false positives.
- **Data-flow and taint analysis:** tracks specific values as they move through the program. This is the technique that finds injection-style flaws, and it is the subject of the next section.
- **Inter-procedural analysis:** extends data-flow and taint tracking across function and method boundaries by following the call graph. Real application flaws almost always cross a function boundary, so inter-procedural analysis is necessary for genuine coverage, and it is the most computationally expensive mode.

A single tool commonly offers several of these and lets a rule choose its technique. Cheap rules run everywhere; expensive inter-procedural taint rules run on a smaller, higher-value set.

## Taint and data-flow analysis

Taint analysis is the core of security-focused SAST. It models untrusted input as tainted and tracks that taint as it propagates through assignments, function calls, and returns. A finding is raised when tainted data reaches a sensitive operation along a path that never passes through a sanitiser. The three roles in the model:

- **Sources:** where untrusted data enters the program.
- **Sinks:** operations that are dangerous if fed untrusted data.
- **Sanitisers:** functions or operations that neutralise the taint, breaking the source-to-sink chain.

Data-flow analysis is the general machinery (tracking how any value moves); taint analysis is data-flow specialised to the security question of whether attacker-controlled data reaches a dangerous operation unchecked. Precision depends on how faithfully the engine models propagation: whether taint survives a string concatenation, a collection insertion and retrieval, a container round-trip, or a framework callback. Under-modelling propagation causes false negatives (a real path missed); over-modelling it causes false positives (a path flagged that a sanitiser or an unreachable branch actually protects).

### Source and sink taxonomy

**Sources (untrusted input):**
- HTTP request parameters, headers, cookies, and body
- File-system reads of user-supplied paths or contents
- Database reads of data that was itself user-supplied
- Message-queue, IPC, and inter-service payloads
- Environment variables and command-line arguments in some contexts

**Sinks (dangerous operations), with the flaw class each enables:**
- SQL or other query construction to SQL injection
- Shell or process execution to OS command injection
- HTML or template output to cross-site scripting
- File-path operations to path traversal
- Outbound URL fetching to server-side request forgery
- Object deserialisation to insecure deserialisation
- Log writing to log injection

**Sanitisers (break the taint chain):**
- Parameterised queries and prepared statements
- Context-aware output encoding (HTML, URL, JavaScript)
- Input validation against an allowlist
- Path canonicalisation followed by an allowlist check

A tool ships with a default catalogue of sources, sinks, and sanitisers per language and framework. The single highest-value tuning action is registering the codebase's own custom sanitisers, because an unrecognised in-house sanitiser makes every path through it a false positive.

## Language and framework coverage

Coverage is not uniform, and the gap is the most common cause of a misleadingly clean result. Two axes vary:

- **Language depth:** taint analysis for long-established web-backend languages (Java, C#, Python, JavaScript and TypeScript, PHP, Ruby, Go) is generally mature, though even here Java and C# models tend to be deeper than Go or Ruby ones. Newer or systems languages (Rust, Kotlin, Swift) are improving but often shallower. Compiled and legacy targets (C and C++, and further out COBOL or assembly) vary widely by tool.
- **Framework awareness:** a taint engine that does not understand a web framework will miss the framework's own sources and sinks (a route parameter binding, an ORM query builder, a template auto-escaping boundary). Framework support, not just language support, determines whether real application flaws are found.

The practical rule: confirm the actual analysis depth for the specific languages and frameworks in the codebase before treating a clean scan as meaningful. Depth advertised for a flagship language does not carry across to every language the tool nominally lists.

## What SAST finds versus what it misses

**Finds well (code-level, statically visible):**
- Injection classes reachable by taint tracking (SQL, command, XSS, path traversal, SSRF, deserialisation)
- Hardcoded secrets and credentials in source
- Weak or misused cryptography (broken algorithms, hardcoded keys, insecure random)
- Unsafe API and function usage against a known-bad catalogue
- Some insecure configuration expressed directly in code

**Misses structurally (no runtime context):**
- Configuration and deployment flaws that live outside the analysed code (server settings, missing security headers, TLS posture)
- Authentication and session behaviour that only manifests at runtime
- Business-logic flaws, where the code is correct but the logic permits an abuse the tool has no specification to judge against
- Reachability in production: SAST can flag a path without knowing whether it is ever exercised, which is a source of false positives, and conversely can miss a flaw hidden behind dynamic dispatch, reflection, or configuration it cannot resolve

This blind spot is not a defect to tune away; it is the definition of static analysis. It is precisely why SAST composes with DAST (which exercises the running system), SCA (which inventories dependencies), and runtime controls rather than substituting for them. The umbrella `application-security` owns that composition; this skill owns the static technique on its own terms.

Two consequences follow for how a clean or noisy result is read. A clean SAST result bounds only the code-level, statically visible flaw classes over the code the tool actually parsed and modelled; it says nothing about runtime, configuration, or logic. And a noisy result is expected, not a malfunction: the false-positive rate is inherent to flagging paths without runtime confirmation, which is why the pipeline discipline in `pipeline-and-triage.md` treats the triaging quality gate as the part that makes SAST usable.
