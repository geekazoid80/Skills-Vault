# AWS Messaging Reference

> SQS, SNS, EventBridge, Kinesis, Step Functions. Prices are US East (N. Virginia).

---

## Service selection decision tree

```
Need async communication between services?
  Simple queue (decouple producer/consumer) -> SQS
    Need ordering + exactly-once? -> SQS FIFO ($0.50/M)
    At-least-once OK? -> SQS Standard ($0.40/M, nearly unlimited TPS)
  Fan-out to multiple consumers -> SNS ($0.50/M publishes)
    Common: SNS -> multiple SQS queues (fan-out + buffering)
  Complex event routing / filtering / third-party -> EventBridge ($1.00/M)
    Content-based filtering, schema registry, archive & replay
  Real-time ordered streaming, multiple consumers -> Kinesis Data Streams
    High-throughput, ordered by partition key, replay up to 365 days
  Workflow orchestration -> Step Functions ($0.025/1000 transitions)
```

---

## SQS deep dive

### Standard queue

- $0.40/M requests (first 1M/mo free)
- Nearly unlimited TPS
- At-least-once delivery (design for idempotency)
- Best-effort ordering (not guaranteed)
- Message retention: 1 to 14 days (default 4)
- Max message size: 256 KB (use S3 Extended Client Library for larger)

### FIFO queue

- $0.50/M requests
- 300 msg/sec without batching, 3,000/sec with batching (10 msg/batch)
- Exactly-once processing (deduplication within 5-minute window)
- Strict ordering within message group
- Use MessageGroupId to parallelise: each group processed in order independently

### Cost example (10M messages/month)

- Standard: 10 x $0.40 = **$4.00/mo**
- FIFO: 10 x $0.50 = **$5.00/mo**
- Both extremely cheap. Choose based on ordering/dedup needs, not cost.

### Cost optimisation

**Long polling:** set `ReceiveMessageWaitTimeSeconds: 20` to reduce empty receives. Short polling returns immediately even if the queue is empty, generating billable requests.

**Batch operations:** `SendMessageBatch` and `ReceiveMessage` with `MaxNumberOfMessages: 10`; 10 messages per request = 10x cost reduction.

**Dead-letter queues:** configure `maxReceiveCount` (e.g., 3). After N failed processing attempts, messages move to the DLQ for investigation. Prevents poison messages from consuming capacity.

**Visibility timeout:** set to 6x your average processing time. Too short = duplicate processing. Too long = delays on failures.

---

## SNS vs EventBridge

### SNS: simple pub/sub

- $0.50/M publishes
- Delivery to SQS/Lambda is free; HTTP is $0.60/M
- Filter policies on message attributes (basic filtering)
- Up to 12.5M subscriptions per topic
- Use for: simple fan-out, alerts, notifications

### EventBridge: smart event bus

- $1.00/M events put on event bus
- Content-based filtering with rules (any JSON field, including nested)
- Schema registry and discovery
- Archive and replay events
- Third-party SaaS integrations (Shopify, Zendesk, Auth0)
- Cross-account and cross-region routing
- Use for: event-driven architectures, microservice integration, complex routing

### When EventBridge over SNS

- Need to filter on event body content (not just attributes)
- Need event archive and replay for debugging
- Need schema registry for event contracts
- Integrating with third-party SaaS events
- Complex routing: 1 event bus -> different targets based on content

---

## Kinesis Data Streams

### Pricing

- **On-Demand:** $0.08/GB ingested, $0.04/hr per stream (auto-scales shards)
- **Provisioned:** $0.015/shard-hour + $0.014/M PUT payload units (25 KB each)
  - 1 shard = 1 MB/s in, 2 MB/s out, 1,000 records/sec in

### Cost example (1 GB/hr ingestion)

- On-Demand: $0.08 x 730 GB/mo + $0.04 x 730 = **$87.60/mo**
- Provisioned (1 shard): $0.015 x 730 + $0.014/M x records = **~$15 to 25/mo**
- Provisioned is significantly cheaper for predictable throughput.

### Kinesis vs SQS

| Aspect | Kinesis | SQS |
|--------|---------|-----|
| Model | Event log (ordered, replay) | Task queue (consumed once) |
| Consumers | Multiple replay same data | One per message |
| Ordering | Per-shard (partition key) | Best-effort (Standard) or per-group (FIFO) |
| Retention | 24 hrs to 365 days | 1 to 14 days |
| Throughput | 1 MB/s per shard (scale by adding shards) | Nearly unlimited |
| Complexity | Higher (shard management) | Lower |

**Decision:** multiple services need to process the same events in order -> Kinesis. One service processes work items consumed once -> SQS.

### Enhanced fan-out

- $0.015/consumer-shard-hour + $0.013/GB retrieved
- Dedicated 2 MB/s throughput per consumer (vs shared 2 MB/s without)
- Use only when >2 consumers per shard need real-time data

---

## Cost comparison at 10M messages/month

| Service | Monthly cost | Ordering | Consumers |
|---------|-------------|----------|-----------|
| SQS Standard | $4.00 | Best-effort | 1 per message |
| SQS FIFO | $5.00 | Strict (per group) | 1 per message |
| SNS + 3 SQS | $5.00 + $12.00 | Per-topic | Fan-out |
| EventBridge | $10.00 | Per-rule | Content-routed |
| Kinesis (1 shard) | ~$15 to 25 | Per-shard | Multiple (replay) |

---

## Messaging cost optimisation

1. **SQS:** always enable long polling (`WaitTimeSeconds: 20`)
2. **SQS:** use batch operations (10 messages/request = 10x savings)
3. **SNS:** use message filtering to avoid delivering messages consumers ignore
4. **EventBridge:** archive only events needed for replay ($0.10/GB stored)
5. **Kinesis:** right-size shards. Enhanced Fan-Out only with >2 consumers/shard
6. **General:** use SQS over Kinesis when you don't need ordering or replay; simpler and cheaper

---

## Common integration patterns

### Fan-out pattern (SNS + SQS)

```
Producer -> SNS Topic -> SQS Queue A (Service A)
                      -> SQS Queue B (Service B)
                      -> SQS Queue C (Service C)
```

Each service gets its own queue (buffering, independent processing rate). SNS message filtering reduces unnecessary deliveries. SQS provides retry and DLQ per consumer.

### Event-driven microservices (EventBridge)

```
Service A -> Custom Event Bus -> Rule 1 -> Lambda (Service B)
                              -> Rule 2 -> SQS (Service C)
                              -> Rule 3 -> Step Functions (Workflow D)
```

Content-based routing. Schema registry for event contracts. Archive for debugging and replay.

### Stream processing (Kinesis + Lambda)

```
Producers -> Kinesis Data Stream -> Lambda Consumer (batch processing)
                                -> Lambda Consumer (real-time analytics)
                                -> Firehose -> S3 (data lake archival)
```

Multiple consumers read the same ordered stream. Lambda event source mapping handles batching and checkpointing.

### Saga pattern (Step Functions + SQS)

```
Step Functions orchestrates:
  1. Reserve Inventory (Lambda)
  2. Process Payment (Lambda)
  3. Ship Order (Lambda)
  On failure at any step:
  -> Compensating transactions (rollback previous steps)
  -> Send failure to DLQ for manual review
```

Step Functions handles retries, timeouts, and compensation logic. Use Standard Workflows for visibility and exactly-once semantics.
