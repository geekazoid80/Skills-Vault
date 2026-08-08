# Cross-cloud service equivalence tables

> Complete mapping of equivalent services across AWS, Azure, and GCP. Use for migration planning, multi-cloud architecture, and cloud selection by service category.

## Compute services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Virtual Machines | EC2 | Virtual Machines | Compute Engine |
| Managed Kubernetes | EKS | AKS | GKE |
| Containers (serverless) | Fargate | Container Apps | Cloud Run |
| Containers (managed) | ECS | Container Instances | (none) |
| Functions (serverless) | Lambda | Functions | Cloud Functions |
| Batch compute | AWS Batch | Batch | Batch |
| Spot or preemptible VMs | Spot Instances | Spot VMs | Spot VMs |
| Bare metal | Outposts (bare metal) | Bare Metal Instances | Bare Metal Solution |
| VMware hosting | VMware Cloud on AWS | Azure VMware Solution | Google Cloud VMware Engine |
| Desktop as a service | WorkSpaces | Azure Virtual Desktop | (none) |
| App hosting (PaaS) | Elastic Beanstalk | App Service | App Engine |

## Storage services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Object storage | S3 | Blob Storage | Cloud Storage |
| Block storage | EBS | Managed Disks | Persistent Disks |
| File storage (NFS) | EFS | Azure Files or NetApp Files | Filestore |
| File storage (SMB) | FSx for Windows | Azure Files | (none) |
| Archive storage | S3 Glacier or Glacier Deep Archive | Blob Archive Tier | Archive Storage |
| Hybrid storage | Storage Gateway | StorSimple or File Sync | (none) |
| Managed Lustre | FSx for Lustre | Managed Lustre | (none) |
| Disk cache | Instance Store | Temp Disk or Ultra Disk | Local SSD |

## Database services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Managed RDBMS | RDS (MySQL, PostgreSQL, MariaDB, Oracle, SQL Server) | Azure SQL, Azure Database for MySQL/PostgreSQL/MariaDB | Cloud SQL (MySQL, PostgreSQL, SQL Server) |
| Cloud-native RDBMS | Aurora (MySQL/PostgreSQL compatible) | Azure SQL Hyperscale | AlloyDB (PostgreSQL compatible) |
| Globally distributed DB | Aurora Global Database | Cosmos DB | Spanner |
| NoSQL document | DocumentDB (MongoDB-compatible) | Cosmos DB (multi-model) | Firestore |
| NoSQL key-value | DynamoDB | Cosmos DB (Table API) or Table Storage | Bigtable |
| In-memory cache | ElastiCache (Redis or Memcached) | Azure Cache for Redis | Memorystore |
| Data warehouse | Redshift | Synapse Analytics | BigQuery |
| Time-series | Timestream | Azure Data Explorer | (use BigQuery or Bigtable) |
| Graph | Neptune | Cosmos DB (Gremlin API) | (use Neo4j on GKE) |
| Ledger or immutable | QLDB | Confidential Ledger | (none) |

## Networking services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Virtual network | VPC | VNet | VPC |
| Subnets | Subnets (per-AZ) | Subnets (regional) | Subnets (regional) |
| Load balancer (L7) | ALB | Application Gateway | HTTP(S) Load Balancer |
| Load balancer (L4) | NLB | Azure Load Balancer | TCP/UDP Load Balancer |
| DNS | Route 53 | Azure DNS | Cloud DNS |
| CDN | CloudFront | Front Door or CDN | Cloud CDN |
| API Gateway | API Gateway | API Management | API Gateway or Apigee |
| VPN | Site-to-Site VPN | VPN Gateway | Cloud VPN |
| Dedicated connection | Direct Connect | ExpressRoute | Cloud Interconnect |
| Service mesh | App Mesh | (use Istio on AKS) | Traffic Director or Istio on GKE |
| Private link to services | PrivateLink | Private Endpoint | Private Service Connect |
| DDoS protection | Shield | DDoS Protection | Cloud Armor |
| Firewall | Network Firewall | Azure Firewall | Cloud Firewall |
| Transit or hub networking | Transit Gateway | Virtual WAN | Network Connectivity Center |
| Global load balancing | Global Accelerator | Front Door | Global HTTP(S) LB (native) |

For AWS VPC depth (Security Groups, NACLs, Transit Gateway routing, VPC Flow Logs), pair with `aws-networking-audit`.

## Security and identity services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Identity and access | IAM (policies plus roles) | Entra ID plus Azure RBAC | IAM (policies plus roles) |
| Directory service | Directory Service (AD) | Entra ID (native AD) | Cloud Identity |
| Secrets management | Secrets Manager | Key Vault (secrets) | Secret Manager |
| Key management | KMS | Key Vault (keys) | Cloud KMS |
| Certificate management | ACM | Key Vault (certificates) or App Service Certs | Certificate Manager |
| Threat detection | GuardDuty | Defender for Cloud | Security Command Center |
| Security posture | Security Hub | Defender for Cloud | Security Command Center |
| WAF | WAF | WAF (via Front Door or App Gateway) | Cloud Armor |
| Managed identities | IAM Roles (for services) | Managed Identities | Service Accounts plus Workload Identity |
| Policy enforcement | Organizations SCPs plus Config | Azure Policy plus Blueprints | Organisation Policy |
| Vulnerability scanning | Inspector | Defender Vulnerability Management | Container Analysis plus Web Security Scanner |

## Serverless and event-driven services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Functions | Lambda | Functions | Cloud Functions |
| Workflow orchestration | Step Functions | Logic Apps or Durable Functions | Workflows |
| Event bus | EventBridge | Event Grid | Eventarc |
| Message queue | SQS | Queue Storage or Service Bus Queues | Cloud Tasks |
| Pub-sub messaging | SNS | Service Bus Topics or Event Grid | Pub/Sub |
| Streaming | Kinesis Data Streams | Event Hubs | Pub/Sub plus Dataflow |
| Scheduled tasks | EventBridge Scheduler | Timer-triggered Functions or Logic Apps | Cloud Scheduler |

## AI and ML services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| ML platform | SageMaker | Azure Machine Learning | Vertex AI |
| Pre-built AI APIs | Rekognition, Comprehend, Translate, Polly, Textract | Cognitive Services (Vision, Language, Speech) | Vision AI, Natural Language, Speech-to-Text, Translation |
| LLM hosting | Bedrock | Azure OpenAI Service | Vertex AI (Model Garden) |
| Custom hardware (ML) | Inferentia and Trainium | (none) | TPUs |
| AutoML | SageMaker Autopilot | Azure AutoML | Vertex AI AutoML |
| MLOps | SageMaker Pipelines | Azure ML Pipelines | Vertex AI Pipelines |
| Notebooks | SageMaker Studio | Azure ML Notebooks | Vertex AI Workbench or Colab Enterprise |

## Data and analytics services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| Data warehouse | Redshift | Synapse Analytics | BigQuery |
| ETL or data integration | Glue | Data Factory | Dataflow or Dataproc |
| Data lake storage | S3 plus Lake Formation | Data Lake Storage Gen2 | Cloud Storage plus BigLake |
| Stream processing | Kinesis Data Analytics | Stream Analytics | Dataflow |
| Data catalog | Glue Data Catalog | Purview | Data Catalog or Dataplex |
| BI or visualisation | QuickSight | Power BI | Looker |
| Hadoop or Spark managed | EMR | HDInsight | Dataproc |
| Search | OpenSearch Service | Cognitive Search | (use Elastic on GKE) |

## DevOps and IaC services

| Category | AWS | Azure | GCP |
|---|---|---|---|
| IaC (native) | CloudFormation | ARM Templates or Bicep | Deployment Manager (deprecated) or Config Connector |
| IaC (cross-cloud) | Terraform, Pulumi, CDK | Terraform, Pulumi, Bicep | Terraform, Pulumi |
| CI/CD | CodePipeline plus CodeBuild | Azure DevOps or GitHub Actions | Cloud Build |
| Container registry | ECR | ACR | Artifact Registry |
| Artifact repository | CodeArtifact | Azure Artifacts | Artifact Registry |
| Monitoring | CloudWatch | Monitor plus Log Analytics | Cloud Monitoring plus Cloud Logging |
| Tracing | X-Ray | Application Insights | Cloud Trace |
| Config management | Systems Manager | Automation or Update Management | OS Config |

## Pricing model comparison

### Compute discount mechanisms

| Mechanism | AWS | Azure | GCP |
|---|---|---|---|
| Auto-discount for sustained use | (none) | (none) | SUDs: up to 30 percent off for VMs running 25 percent or more of month |
| Reserved (1-year) | Up to 40 percent off | Up to 40 percent off | CUDs: up to 37 percent off |
| Reserved (3-year) | Up to 60 percent off | Up to 60 percent off | CUDs: up to 55 percent off |
| Flexible commitment | Savings Plans (compute family) | Savings Plans (compute) | CUDs (compute or resource-based) |
| Bring your own license | (none) | Azure Hybrid Benefit (Windows plus SQL): up to 85 percent savings | (none) |
| Custom machine types | (none) | (none) | Yes (pay for exact vCPU and RAM needed) |
| Spot or preemptible | Up to 90 percent off (2-minute warning) | Up to 90 percent off (30-second notice) | Up to 91 percent off (30-second notice) |

### Network egress pricing

| Tier | AWS | Azure | GCP |
|---|---|---|---|
| Free egress per month | 100 GB | 100 GB | 200 GB |
| First 10 TB per month | 0.09 USD per GB | 0.087 USD per GB | 0.12 USD per GB (premium) or 0.085 USD per GB (standard) |
| Same-region cross-AZ | 0.01 USD per GB each direction | Free | Free |

**Key insight.** Azure and GCP do not charge for cross-AZ traffic within a region. AWS charges 0.01 USD per GB each direction, which compounds for distributed architectures.

### Storage pricing (hot tier, per GB per month)

| Metric | AWS S3 Standard | Azure Blob Hot | GCP Standard |
|---|---|---|---|
| Storage | 0.023 USD per GB | 0.018 USD per GB | 0.020 USD per GB |
| GET (per 1K) | 0.0004 USD | 0.004 USD | 0.004 USD |
| PUT (per 1K) | 0.005 USD | 0.05 USD | 0.05 USD |

### Support plan comparison

| Tier | AWS | Azure | GCP |
|---|---|---|---|
| Business or Standard | 100 USD per month or 5-10 percent of usage | 100 USD per month | 500 USD per month (Enhanced) |
| Enterprise or Premium | 15K USD per month or 3-10 percent of usage | Custom pricing (Unified) | 12.5K USD per month (Premium) |
| Critical response SLA | under 15 minutes | under 15 minutes | under 15 minutes |
| TAM included | Enterprise | Unified (CSAM) | Premium |

### Free tier comparison

| Aspect | AWS | Azure | GCP |
|---|---|---|---|
| Duration | 12-month plus always-free | 12-month plus always-free | 90-day 300 USD credit plus always-free |
| Functions (always free) | 1M invocations per month | 1M executions per month | 2M invocations per month |
| Always-free compute | (none) | (none) | 1 e2-micro (US regions) |
