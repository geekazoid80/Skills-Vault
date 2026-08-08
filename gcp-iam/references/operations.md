# GCP IAM operations

## Policy binding commands

```bash
# Grant a role to a group at project level
gcloud projects add-iam-policy-binding my-project \
  --member="group:data-team@example.com" \
  --role="roles/bigquery.dataViewer"

# Grant a role with an IAM Condition (requires --condition flag)
gcloud projects add-iam-policy-binding my-project \
  --member="group:data-team@example.com" \
  --role="roles/storage.objectViewer" \
  --condition='title=prod-only,expression=resource.name.startsWith("projects/_/buckets/prod-")'

# Remove a binding
gcloud projects remove-iam-policy-binding my-project \
  --member="user:alice@example.com" \
  --role="roles/editor"

# View the full IAM policy for a project (JSON)
gcloud projects get-iam-policy my-project --format=json

# Grant a role at folder level
gcloud resource-manager folders add-iam-policy-binding FOLDER_ID \
  --member="group:platform@example.com" \
  --role="roles/compute.admin"

# Grant a role at organisation level
gcloud organizations add-iam-policy-binding ORG_ID \
  --member="group:security@example.com" \
  --role="roles/securitycenter.admin"

# Create a service account
gcloud iam service-accounts create app-backend \
  --display-name="App Backend Service Account" \
  --project=my-project

# Grant role to service account
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:app-backend@my-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# List predefined roles for a service
gcloud iam roles list --filter="name:roles/storage.*"

# Create a custom role
gcloud iam roles create customStorageReader \
  --project=my-project \
  --title="Custom Storage Reader" \
  --permissions=storage.objects.get,storage.objects.list,storage.buckets.get
```

---

## Workload Identity Federation setup patterns

### GitHub Actions -> GCP

```bash
# 1. Create a pool
gcloud iam workload-identity-pools create github-pool \
  --location=global \
  --display-name="GitHub Actions Pool"

# 2. Create the OIDC provider
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository == 'my-org/my-repo'"

# 3. Grant impersonation to matching principals
PROJECT_NUM=$(gcloud projects describe my-project --format="value(projectNumber)")
gcloud iam service-accounts add-iam-policy-binding \
  deploy-sa@my-project.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUM}/locations/global/workloadIdentityPools/github-pool/attribute.repository/my-org/my-repo"

# 4. In GitHub Actions workflow:
# - id-token: write  (workflow permission)
# - uses: google-github-actions/auth with workload_identity_provider and service_account
```

### AWS workload -> GCP

```bash
# Create pool and AWS provider
gcloud iam workload-identity-pools providers create-aws aws-provider \
  --location=global \
  --workload-identity-pool=aws-pool \
  --account-id="123456789012"
# attribute-mapping defaults: google.subject = assertion.arn
```

The AWS workload exchanges its instance metadata credentials for a GCP access token via the Security Token Service endpoint, using the `google-auth-library` or `Application Default Credentials` with the provider credentials config file.

---

## Organisation policy authoring

```bash
# Deny service account key creation org-wide
cat > disable-sa-keys.yaml << 'EOF'
name: organizations/ORG_ID/policies/iam.disableServiceAccountKeyCreation
spec:
  rules:
  - enforce: true
EOF
gcloud org-policies set-policy disable-sa-keys.yaml

# Restrict resource creation to US and EU regions
cat > resource-locations.yaml << 'EOF'
name: organizations/ORG_ID/policies/gcp.resourceLocations
spec:
  rules:
  - values:
      allowedValues:
      - in:us-locations
      - in:eu-locations
EOF
gcloud org-policies set-policy resource-locations.yaml

# Allow policy exceptions at project level (further restrict, not expand)
gcloud org-policies set-policy project-override.yaml --project=sandbox-project

# Describe the effective policy at a resource (including inherited)
gcloud org-policies describe constraints/iam.disableServiceAccountKeyCreation \
  --project=my-project --effective
```

Test org policy changes in a sandbox project or folder first. Boolean constraints cannot be relaxed at lower levels; list constraints can only be further restricted (not expanded) at lower levels.

---

## VPC Service Controls dry-run workflow

1. **Create a perimeter in dry-run mode** via the Cloud Console or `gcloud access-context-manager perimeters create --type=REGULAR --perimeter-type=REGULAR` with `--policy=POLICY_ID`.
2. **Set to dry-run**: when creating, the perimeter starts in dry-run mode by default.
3. **Monitor violations** in Cloud Audit Logs for at least 7 days:
   ```bash
   gcloud logging read \
     'protoPayload.metadata."@type"="type.googleapis.com/google.cloud.audit.VpcServiceControlAuditMetadata" AND protoPayload.metadata.violationReason!=""' \
     --project=my-project --format=json
   ```
4. **Create ingress/egress rules** for each legitimate violation identified.
5. **Re-test in dry-run** until no violations remain for known-good traffic.
6. **Convert to enforcement**: `gcloud access-context-manager perimeters update PERIMETER_NAME --policy=POLICY_ID` (set `--no-dry-run-mode`).

---

## IAM Recommender review and apply workflow

```bash
# List active recommendations for a project
gcloud recommender recommendations list \
  --recommender=google.iam.policy.Recommender \
  --project=my-project \
  --location=global \
  --format=json

# Mark a recommendation as claimed (in-progress)
gcloud recommender recommendations mark-claimed \
  RECOMMENDATION_ID \
  --recommender=google.iam.policy.Recommender \
  --project=my-project \
  --location=global \
  --etag=ETAG

# Apply the recommended change (e.g., replace roles/editor with roles/storage.objectViewer)
# Apply the IAM binding changes manually or via Terraform, then mark succeeded:
gcloud recommender recommendations mark-succeeded \
  RECOMMENDATION_ID \
  --recommender=google.iam.policy.Recommender \
  --project=my-project \
  --location=global \
  --etag=ETAG

# Dismiss a recommendation (false positive / intentional access)
gcloud recommender recommendations mark-dismissed \
  RECOMMENDATION_ID \
  --recommender=google.iam.policy.Recommender \
  --project=my-project \
  --location=global \
  --etag=ETAG
```

Run the recommender review monthly. Prioritise organisation-level and folder-level recommendations as they have the widest blast radius. Integrate into access review cycles.

---

## Access troubleshooting with Policy Analyzer

Policy Analyzer answers "which principals have this permission on this resource?" or "can this principal access this resource?":

```bash
# Who has storage.objects.get on a specific bucket?
gcloud asset search-all-iam-policies \
  --scope=projects/my-project \
  --query='policy:roles/storage.objectViewer AND resource:projects/my-project/buckets/my-bucket'

# Use the Policy Troubleshooter for specific access check
gcloud policy-troubleshoot iam \
  --principal-email=alice@example.com \
  --permission=storage.objects.get \
  --resource=//storage.googleapis.com/projects/_/buckets/my-bucket
```

For VPC Service Controls violations, check Cloud Audit Logs under `protoPayload.metadata` for `violationReason` and `resourceNames` fields to identify which service and resource triggered the perimeter.

**Cloud Audit Log admin activity**: every IAM `setIamPolicy` call is recorded in Cloud Audit Logs under `activity` log type. Use `protoPayload.methodName = "SetIamPolicy"` filter to audit IAM changes.
