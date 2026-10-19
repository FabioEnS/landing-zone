![Landing Zone Architecture Diagram](landing-zone-diagram.png)


## testing

Validated that the NAT gateway, which allows private resources to reach the internet without being reachable from it, actually works by launching a temporary EC2 test instance — a small virtual server — into a private subnet, a part of the network with no direct public internet access. Connected to it using SSM Session Manager, a secure method that doesn't require SSH keys or open ports, and confirmed outbound internet access by running a curl request against Google.


sh-5.2$ curl -I https://www.google.com
HTTP/2 200 
content-type: text/html; charset=ISO-8859-1
content-security-policy-report-only: object-src 'none';base-uri 'self';script-src 'nonce-ZuusLek3szfhzlijv5TQNw' 'strict-dynamic' 'report-sample' 'unsafe-eval' 'unsafe-inline' https: http:;report-uri https://csp.withgoogle.com/csp/gws/other-hp
accept-ch: Sec-CH-Prefers-Color-Scheme
p3p: CP="This is not a P3P policy! See g.co/p3phelp for more info."
date: Wed, 07 Oct 2026 01:32:34 GMT
server: gws
x-xss-protection: 0
x-frame-options: SAMEORIGIN
expires: Wed, 07 Oct 2026 01:32:34 GMT
cache-control: private

During testing, the initial Session Manager connection failed. SSM Session Manager is a service that lets you open a secure shell into an EC2 instance without SSH keys or open inbound ports — but it requires the instance itself to have permission to register with the SSM service in the background. The instance was missing this permission, so the connection failed. This was resolved by creating an IAM role — essentially a set of permissions an AWS resource can assume — and attaching the AmazonSSMManagedInstanceCore policy to it, which is an AWS-managed policy that specifically grants the permissions needed for SSM to manage an instance. An instance profile was then created to let the EC2 instance actually use that role, and once attached, the Session Manager connection succeeded.

## Version Control
This project uses Git for version control, allowing changes to be tracked over time and rolled back if something breaks

## Staging Environment Setup

Created the staging environment by copying the dev configuration as a base. Updated the Terraform backend key — the file path in S3 where Terraform stores that environment’s state file, keeping dev and staging state separate — to staging/terraform.tfstate. Changed the CIDR block, which defines the range of IP addresses available to the network, for the staging VPC to 10.1.0.0/16, and updated all four subnets accordingly: public_1 to 10.1.1.0/24, public_2 to 10.1.2.0/24, private_1 to 10.1.3.0/24, and private_2 to 10.1.4.0/24, to avoid IP range conflicts with dev’s 10.0.0.0/16 range.”
Changes were committed to Git to track this milestone in the project’s history.

## Lessons Learned

### 1. IAM names must be unique across the whole AWS account

**What happened:** I copied my dev environment into production. When I ran
`terraform apply`, it failed with the error "Role with name
landing-zone-ssm-role already exists."

**Why it happened:** Most things in AWS (like a VPC or subnet) live inside
one environment. IAM roles and instance profiles do not. They are shared
across the entire AWS account, so two environments cannot use the same
name. Dev had already claimed it.

**How I fixed it:** I renamed the production resources to include the
environment name:
- `landing-zone-ssm-role` became `landing-zone-production-ssm-role`
- `landing-zone-ssm-profile` became `landing-zone-production-ssm-profile`

**Takeaway:** When copying one environment to another, put the environment
name in the name of every account-wide resource (IAM roles, instance
profiles, S3 buckets). Resources that live inside one environment are safer
to copy as they are.

### 2. Cleaning up a leftover test instance in staging

**What happened:** When I ran `terraform plan` in staging, it showed
"1 to add, 0 to change, 1 to destroy." Terraform wanted to replace an old
test EC2 instance.

**Why it happened:** The Amazon Linux AMI (the machine image the server is
built from) had been updated since the instance was first created. Terraform
treats an AMI change as a reason to destroy and rebuild the server.

**How I fixed it:** The instance was only for testing connectivity and was
not part of the core landing zone. Rather than rebuild something I didn't
need, I deleted its block from `main.tf` and ran `terraform apply`, which
destroyed it cleanly.

**Takeaway:** Always read the plan before applying. Decide whether each
resource is core infrastructure or just a disposable test. Removing
disposable resources saves money and keeps the environment matching what I
actually intend to run.

### 8. Leftover test resources in production and staging
**What happened:** After fixing the stray EC2 instance (issue 7), I checked the other environments for leftovers. Production's `main.tf` still had the test instance (`aws_instance "test"`) and three IAM blocks that existed only to let me connect to it (`aws_iam_role`, `aws_iam_role_policy_attachment`, `aws_iam_instance_profile`). Staging had the same three IAM blocks, but its test instance had already been removed in an earlier cleanup.

**Why it happened:** Production and staging were built by copying dev's `main.tf`. Dev's file still contained the temporary NAT gateway test setup, so the copies carried it along. Terraform builds whatever is in the code, so the test resources were created again in production.

**Key concept: code vs. state.** Terraform keeps two records: the code (what I *want*) and the state file (what Terraform *thinks exists*). When I terminated the instance by hand in the AWS console, the state file still listed it, so Terraform would have rebuilt it on the next apply. Resources should be removed through Terraform, not by hand in the console.

**Fix:**
1. Deleted the test instance and the three IAM blocks from production's `main.tf`, then ran `terraform plan`, which showed 0 to add, 0 to change, 3 to destroy (the instance was already gone from AWS, so Terraform only needed to clear the three IAM resources).
2. Ran `terraform apply`: 0 added, 0 changed, 3 destroyed.
3. Did the same in staging: deleted the three leftover IAM blocks, plan showed 3 to destroy, apply destroyed all 3.

**Lessons:**
- Before copying one environment's config to another, remove any temporary test resources first.
- Always read the `terraform plan` summary before applying. It's a free preview of what will be created or destroyed.
- Remove resources through Terraform instead of the console, so the code and state stay in sync.
- After a cleanup, run `terraform plan` in every environment. "0 to add, 0 to change, 0 to destroy" confirms everything matches.

### 9. Dev environment had staging's settings in it
**What happened:** While cleaning up leftover test resources in dev, I ran `terraform plan` and it said it wanted to create 19 resources (13 after I removed the test blocks). That was wrong. Dev's VPC, subnets, and route tables were already built, so a healthy plan should have said "no changes." Reading the plan output, I noticed the VPC address was `10.1.0.0/16`, which is staging's address range. Dev is supposed to use `10.0.0.0/16`.

**Root cause:** Dev's `main.tf` contained staging's settings:
- The backend key pointed at `staging/terraform.tfstate` instead of `dev/terraform.tfstate`
- The VPC `cidr_block` was `10.1.0.0/16` instead of `10.0.0.0/16`
- All four subnet `cidr_block` values used the `10.1.x.0/24` range instead of `10.0.x.0/24`

The exact cause is unclear, but most likely a copy-paste mix-up from when staging was built by copying dev's file and changing its values.

**Key concepts:**
- **State file:** Terraform's record of what it has built. Each environment has its own, so Terraform knows which resources belong to which environment.
- **Backend key:** The file name Terraform uses to find that environment's state file in the S3 bucket. If the key points to the wrong (or an empty) state file, Terraform thinks nothing exists and plans to build everything again. That was the "19 to add."
- **CIDR block:** The range of private IP addresses a network is allowed to use. Each environment gets its own range (dev `10.0.0.0/16`, staging `10.1.0.0/16`) so the networks never overlap.

**What I ruled out first:**
- The AWS region: dev's provider block was correctly set to `us-east-1` (N. Virginia), matching where the resources live.
- Missing resources: the dev VPC and subnets existed in the console, so nothing had been deleted.

**Fix:**
1. Changed the backend key back to `dev/terraform.tfstate`.
2. Changed the VPC `cidr_block` back to `10.0.0.0/16`.
3. Changed the four subnet `cidr_block` values back to `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`, and `10.0.4.0/24`.
4. Ran `terraform init -reconfigure` so Terraform reconnected to the correct state file.
5. Ran `terraform plan`: 0 to add, 0 to change, 2 to destroy. The two were the NAT gateway and Elastic IP from my earlier connectivity testing.
6. Ran `terraform apply`. It stopped with an error on the Elastic IP (see "A second hiccup" below). Ran `terraform plan` again (1 to destroy), then `terraform apply` a second time: 0 added, 0 changed, 1 destroyed.

Dev, staging, and production are now clean of test leftovers.

**A second hiccup: Elastic IP error during apply**
**What happened:** The first apply failed while releasing the Elastic IP (EIP) with an error saying the network interface ID does not exist, and Terraform stopped.

**Why:** An Elastic IP is a fixed public IP address. It was attached to the NAT gateway through a network interface. I had already deleted the NAT gateway by hand in the console after testing, which removed that network interface, but Terraform's state file still listed both resources. When Terraform tried to detach the EIP from an interface that was already gone, AWS returned the error.

**Fix:** Ran `terraform plan` to see what was left (1 to destroy, only the EIP), then ran `terraform apply` again. It completed cleanly.

**Lessons:**
- Never apply a plan that wants to create everything when the infrastructure already exists. That's a sign something is pointed at the wrong place. Stop and investigate.
- After copying one environment's file to another, search the new file for every environment-specific value: backend key, CIDR blocks, resource names, and tags.
- Read the plan summary before every apply. It's a free preview and it caught this before any damage was done.
- Check every environment's plan after any change. All three (dev, staging, production) should show "no changes."
- An error partway through an apply doesn't mean everything failed. Run `terraform plan` to see what's left, then apply again.
- Deleting resources by hand in the console leaves Terraform's state out of date, which can cause errors later. Remove resources through Terraform so the code and state stay in sync.

## Environments

This project uses three separate Terraform environments, each with its own
state file, so changes in one cannot accidentally affect another.

### dev
The primary working environment. All new features are built and tested
here first before being copied to staging or production.

### staging
A copy of the dev environment, used to verify changes work correctly
before they reach production. Also used for one-off connectivity testing.

### production
The environment meant to represent a live, real-world deployment. Changes
are only copied here once they've been proven out in dev and staging.

Each environment has its own Terraform state, stored separately in S3
(for example, `dev/terraform.tfstate`, `staging/terraform.tfstate`,
`production/terraform.tfstate`), and its own `main.tf` with environment-
specific values such as CIDR blocks and resource names.

## AWS Accounts

This project uses AWS Organizations to separate environments into fully
isolated AWS accounts, rather than relying on a single account with
separate Terraform state files.

| Account              | Purpose                                   | Email                          |
|-----------------------|--------------------------------------------|----------------------------------|
| landing-zone-dev        | Primary development and testing           | esant.user+dev@gmail.com        |
| landing-zone-staging    | Pre-production verification                | esant.user+staging@gmail.com    |
| landing-zone-production | Production-representative deployment       | esant.user+production@gmail.com |
| landing-zone-security   | Centralized logging and audit (CloudTrail, GuardDuty) | esant.user+security@gmail.com   |

All accounts are managed under a single AWS Organization, with the
original account serving as the management account. Access is being
configured through IAM Identity Center so each account can be reached
without separate passwords.

## Project Overview: AWS Landing Zone

### What This Is
This project is a landing zone — the foundational infrastructure and 
guardrails a company sets up before deploying any real applications. 
It's not an application itself; it's the secure, organized environment 
that applications would later run inside. Building this is genuinely 
day-one work for a cloud/DevOps team at a real company.

### Environments
The project includes three separate, identical environments: dev, 
staging, and production. 
- Dev is for experimenting freely, where mistakes are expected and cheap.
- Staging mirrors production closely and is used to validate changes 
  realistically before they go live.
- Production is the live environment, held to a higher standard, with 
  changes made carefully and deliberately.

Keeping these separate limits risk (bugs or breakage stay contained) 
and limits cost exposure (mistakes are caught before they reach the 
account that matters most).

### Networking Layer
- **VPC (Virtual Private Cloud):** A private, isolated network — like 
  a fenced piece of land. Nothing enters or exits without explicit 
  permission.
- **Subnets:** The VPC is divided into public and private subnets. 
  Public subnets can be reached from the internet; private subnets 
  cannot be reached from the internet, but can still reach out.
- **Internet Gateway:** The single doorway between the VPC and the 
  public internet, used only by the public subnets.
- **NAT Gateway:** Lets resources in the private subnets reach out to 
  the internet (e.g., for software updates) without ever being 
  reachable from the internet themselves.
- **Route Tables:** The "street signs" inside the VPC that direct 
  traffic — public subnets route toward the internet gateway, private 
  subnets route toward the NAT gateway.

### Security Layer
- **Security Groups:** A firewall attached to individual servers. 
  Only explicitly allowed traffic (e.g., web traffic on ports 80/443) 
  is let through; everything else is blocked by default. This follows 
  the principle of least privilege — only open what's actually needed.
- **Service Control Policies (SCPs):** Account-wide guardrails applied 
  across the whole AWS Organization, enforced regardless of individual 
  account permissions. Five were implemented:
  1. **Deny root user actions** — blocks use of the all-powerful root 
     login for routine work, forcing traceable, named-user access instead.
  2. **Restrict regions** — locks activity to two approved AWS regions, 
     making anything outside them an instant red flag.
  3. **Deny leaving the organization** — prevents any member account 
     from detaching itself and escaping the organization's guardrails.
  4. **Protect security services** — prevents CloudTrail (the audit 
     log) and IAM Identity Center (the access/login system) from being 
     disabled or tampered with.
  5. **Restrict expensive services** — hard-blocks creation of costly 
     services (e.g., SageMaker, Redshift) and oversized EC2 instances, 
     preventing accidental high bills.

     Security and Governance Decisions
These choices were built into the landing zone from the start. Each one is a security and governance decision, and the reason behind it is noted here.
• Root account MFA: Enabled multi-factor authentication on the root user to prevent unauthorized access to the account's most privileged identity, since root access bypasses all other permission controls.
• Terraform state bucket: Enabled versioning and SSE-S3 encryption on the state bucket to protect against accidental state loss and ensure data at rest is secured. Public access is fully blocked to prevent exposure of sensitive infrastructure details stored in the state file.
• IAM Identity Center with least privilege: Access is granted through Identity Center using scoped permission sets rather than long-lived IAM user credentials, following least privilege principles and reducing the blast radius if any credential is compromised.

### Multi-Account Structure
The project uses AWS Organizations to separate concerns into dedicated 
accounts (dev, staging, production, security), grouped into 
organizational units (Workloads, Security), with centralized identity 
management via IAM Identity Center.

### Real Incident: Stray Resource Cost
During development, a budget alert caught an unexpected ~$9.38 charge 
from a leftover EC2 test instance. Root-cause investigation traced it 
to test resources mistakenly copied between environment configs during 
setup — including a separate incident where dev's configuration file 
was found to contain staging's settings entirely. Both were resolved, 
documented in the README's "Issues Encountered" section, and directly 
informed the decision to add the expensive-service SCP guardrail above.

## Cost Lessons Learned

### The Incident
An AWS budget alert fired after spending crossed the $10 threshold set 
at project start. Investigating through the console revealed a running 
EC2 t3.micro instance that wasn't supposed to be there, costing roughly 
$9.38.

### Root Cause
Tracing it back, the instance came from test resources (an EC2 instance 
plus supporting IAM role/policy resources, originally created to 
validate NAT gateway connectivity) that had been copied into the 
production and staging environment files during setup, instead of 
being removed after testing was finished.

A related issue surfaced during cleanup: the dev environment's 
configuration file was found to contain staging's settings entirely 
(wrong state file path, wrong network address ranges) — a copy-paste 
mix-up from when staging was built using dev's file as a starting 
point. This could have caused dev's infrastructure to silently 
conflict with staging's.

### Resolution
- Removed all leftover test resources from production and staging 
  configuration files, confirmed via `terraform plan` showing no 
  unexpected changes.
- Corrected dev's configuration back to its own settings and cleaned 
  up genuine leftover resources (a NAT gateway and its IP address) 
  that were no longer needed.
- Verified all three environments (dev, staging, production) were 
  clean and consistent afterward.

### Prevention Going Forward
This incident directly motivated one of the account-wide guardrails 
built afterward: a policy blocking the creation of costly services 
and oversized servers across all accounts, so a similar stray resource 
could never generate a surprise charge again.

### Takeaway
Infrastructure-as-code makes resources easy to copy — but that also 
makes it easy to accidentally copy things that shouldn't be reused 
across environments. Catching this early, via a low budget threshold 
and routine `terraform plan` checks, kept the cost small and turned 
into a concrete improvement to the project's guardrails.