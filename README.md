# S3 Canary Tripwire

A lightweight AWS detection engineering lab that deploys a monitored decoy object ("honeytoken") inside a private Amazon S3 bucket and triggers an alert via Amazon EventBridge and Amazon SNS when a `GetObject` read attempt is recorded through AWS CloudTrail data events.

## Why Use a Canary Tripwire?

High-volume cloud audit logs often create alert fatigue. A canary tripwire uses a clearly marked, fictitious credential file placed where legitimate workloads should never read it:

- **High signal-to-noise ratio:** Legitimate automation has no reason to access the decoy key.
- **Early detection:** Any `GetObject` call against the canary object indicates potential reconnaissance or unauthorized credential hunting.
- **Reproducible lab:** Provisioned with Terraform and paired with a Python simulation script and GitHub Actions validation.

## Architecture & Detection Flow

```mermaid
flowchart LR
    A[Access / Simulation Script] -->|s3:GetObject| B[Private S3 Bucket + Decoy Object]
    B -->|S3 Data Event| C[AWS CloudTrail]
    C -->|Matching Event Pattern| D[Amazon EventBridge Rule]
    D -->|Publish Alert| E[Amazon SNS Topic -> Email]