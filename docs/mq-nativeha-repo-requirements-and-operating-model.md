# MQ NativeHA Repository Requirements and Operating Model

## Purpose

This repository automates IBM MQ NativeHA queue manager lifecycle using Ansible,
GitOps target repositories, ArgoCD/OpenShift GitOps, OpenShift, Vault Secrets
Operator, and an internal image registry.

The primary responsibility of this repository is to generate and update
Kubernetes/GitOps artifacts in the correct target Git repository. The normal
source of truth is Git, not live cluster state.

This document is the repository-wide operating model. When a design choice,
automation behavior, AAP survey expectation, pull request rule, or Day-2
boundary is approved, it should be reflected here.

Unless explicitly instructed for an operational investigation, automation must
not directly deploy queue managers to OpenShift and must not call ArgoCD.

## Repository Pillars

### `NativeHA_Qmgr_Automate_Deployment/`

Queue manager onboarding.

Responsibilities:

- Validate Create/Update survey inputs.
- Derive queue manager identity.
- Derive namespace.
- Derive storage sizing.
- Derive Vault security zone.
- Derive NativeHA/CRR deployment shape.
- Generate Base + Overlays manifests into the target repo.
- Generate ArgoCD Application YAML artifacts into the target repo.
- Publish generated artifacts through the configured target repo change mode.
- Discover queue manager state from Git only.

Create auto-increments queue manager sequence from the target Git repository.
Update regenerates one specific existing queue manager path.

### `NativeHA_Cert_Management/`

Certificate lifecycle.

Responsibilities:

- Use the same naming and identity maps as queue manager onboarding.
- Manage certificate request/registry flows.
- Manage Vault/DummyCertManager related certificate data.
- Keep certificate identity aligned with queue manager identity.

### `NativeHA_Image_Upgrade/`

Day-2 MQ image/version update.

Responsibilities:

- Update only existing `qm-image-patch.yaml` files in target repo overlays.
- Publish image/version changes through the configured target repo change mode.
- Avoid OpenShift and ArgoCD mutation.

This workflow is independent from queue manager onboarding and must not be placed
inside `NativeHA_Qmgr_Automate_Deployment/`.

### `NativeHA_Role_Switch/`

Day-2 NativeHA CRR role switch.

Responsibilities:

- Update regional role patch artifacts.
- Switch `Live` and `Recovery` roles through GitOps artifacts.
- Publish role changes through the configured target repo change mode.
- Remain independent from queue manager onboarding.

This workflow is independent from queue manager onboarding and must not be placed
inside `NativeHA_Qmgr_Automate_Deployment/`.

### `nativeha_templates/`

Shared source of truth.

Responsibilities:

- Global control variables.
- Base templates.
- Overlay templates.
- Static MQSC/INI/scripts files.
- Certificate registry data.

Current layout:

```text
nativeha_templates/
  base/
    qmgr_templates/
    mqsc/
    ini/
    scripts/
    secrets/
    monitoring/
  overlays/
  global_vars/
  cert_registry/
```

All Jinja templates should live under `nativeha_templates/base/` or
`nativeha_templates/overlays/`.

Static files should live under `nativeha_templates/base/` subdirectories and
should only be templated when variable substitution is actually required.

## AAP Project Sync and Collections

AAP may point at the repository root or directly at one of the workflow
directories. Each supported entry point must have a local
`collections/requirements.yml` so project sync can install the required
collections regardless of SCM project root.

Supported requirements files:

```text
collections/requirements.yml
NativeHA_Qmgr_Automate_Deployment/collections/requirements.yml
NativeHA_Cert_Management/collections/requirements.yml
NativeHA_Image_Upgrade/collections/requirements.yml
NativeHA_Role_Switch/collections/requirements.yml
```

Before rerunning an AAP job after automation code changes, sync the AAP project.
Otherwise AAP may continue executing stale task logic, especially around
sequence discovery, PR matching, and changelog generation.

## Target Repository Layout

Queue managers are generated into environment-specific target repositories.

Current environment-to-repository rule:

- DEV uses the DEV target repo.
- QA1 and QA2 share the QA target repo and are separated by
  `queue_managers/QA1/` and `queue_managers/QA2/`.
- QA3 uses the QA3 target repo.
- PROD uses the PROD target repo.
- All current target repos use `develop` as the deployment branch.

For environments with environment subdirectories such as QA2 and QA1:

```text
queue_managers/<ENV>/<qmgr_name>/
  base/
    qmgr.yaml
    kustomization.yaml
    mqsc/
    ini/
    scripts/
    secrets/
    monitoring/
  overlays/
    <region>/
      kustomization.yaml
      <region_label>-patch-role.yaml
      qm-image-patch.yaml
```

ArgoCD Application manifests are generated into a shared application directory:

```text
argocd_mq_applications/<region>/<qmgr_name>_<region>_argocd_app.yaml
```

The automation may generate these ArgoCD Application YAMLs, but must not apply
them to OpenShift unless explicitly requested.

Every queue manager target path should carry its own `CHANGELOG.md`:

```text
queue_managers/<ENV>/<qmgr_name>/CHANGELOG.md
```

The automation prepends one entry per PR update to the queue-manager changelog
so managers and approvers can see what changed without reverse-engineering the
diff. The root `CHANGELOG.md` may exist for repository-level release notes, but
automation PRs should not require a root changelog edit because parallel PRs
will otherwise conflict at the top of the same file.

## Naming and Identity

Queue manager names use:

```text
<app_sys_id><2-char-env-code><seq>
```

Example:

```text
app1q2001
```

Namespaces use:

```text
<app_sys_id>-mq-<3-char-env-code>-<seq>
```

Example:

```text
app1-mq-qa2-001
```

Environment maps:

```yaml
env_qmgr_abbr:
  DEV:  DV
  QA1:  Q1
  QA2:  Q2
  QA3:  Q3
  PROD: PR

env_namespace_abbr:
  DEV:  DEV
  QA1:  QA1
  QA2:  QA2
  QA3:  QA3
  PROD: PROD
```

The queue manager and certificate workflows must derive names from the same
maps:

- `env_qmgr_abbr`
- `env_namespace_abbr`
- `vault_security_zones`

Production-style certificate and VSO Vault paths use:

```text
<app_prefix>/ibm-mq/<ENV>/<NAMESPACE>/<QMGR>/<cert-subpath>
```

Example:

```text
app1/ibm-mq/QA2/app1-mq-qa2-001/APP1Q2001/app-pki
```

## Queue Manager Create Behavior

Create inputs:

```text
qm_action=create
app_sys_id=<3-character application id>
mq_environment=<DEV|QA1|QA2|QA3|PROD>
total_volume_24h=<message volume>
avg_msg_size=<average message size>
```

The user must not provide `qmgr_name` for Create.

Create must:

1. Normalize `qm_action`.
2. Validate inputs.
3. Clone the target repo and target branch.
4. Discover existing queue manager directories from the target Git branch.
5. Discover pending queue manager create requests from remote automation branch
   names.
6. Auto-increment to the next free sequence across merged and pending work.
7. Derive `qmgr_name`.
8. Derive namespace.
9. Derive Vault zone.
10. Derive sizing.
11. Generate Base + Overlays artifacts.
12. Generate ArgoCD Application YAML artifacts.
13. Publish target repo changes through the configured change mode.
14. Clean the temporary working directory in an `always` block.

Important:

Create discovery is Git-only by design. It does not inspect OpenShift.

Create discovery must count both:

- merged queue manager directories such as
  `queue_managers/QA2/app1q2001/`, and
- pending remote automation branches such as
  `feature/app1/app1q2002-qmgr`.

Remote branch discovery should list all remote heads and filter branch names in
Ansible. Do not rely on a narrow `git ls-remote` glob such as `app1/*`, because
provider and Git pattern behavior can miss nested branch names.

Example approved behavior:

```text
develop contains: queue_managers/QA2/app1q2001/
open PR branch:  feature/app1/app1q2002-qmgr
next Create:     app1q2003
```

Create must not reuse an existing open create PR for the same queue manager.
If Create resolves `app1q2002` while an open PR already exists for
`feature/app1/app1q2002-qmgr`, that is a discovery/collision problem. The job
should fail clearly instead of trying to reapply the same generated files onto
the existing branch.

If the target Git repo has no `app1q2001` directory but OpenShift still has old
`app1q2001` PVCs, Create can generate `app1q2001` again. That can cause old PVC
reuse if ArgoCD deploys it into the same namespace/name.

## Queue Manager Update Behavior

Update inputs:

```text
qm_action=update
mq_environment=<DEV|QA1|QA2|QA3|PROD>
qmgr_name=<existing qmgr name>
total_volume_24h=<message volume>
avg_msg_size=<average message size>
```

Update must:

1. Normalize `qm_action`.
2. Validate `qmgr_name` matches the supplied environment code.
3. Trust `mq_environment` for repo and branch selection.
4. Parse `app_sys_id` and sequence from `qmgr_name`.
5. Clone the target repo and target branch.
6. Validate that the specific target path exists.
7. Regenerate only that queue manager path.
8. Publish target repo changes through the configured change mode.
9. Clean the temporary working directory.

## Target Repo Change Mode

Target repository publication is controlled by one global variable in
`nativeha_templates/global_vars/nativeha_qmgr_control_vars.yaml`:

```yaml
target_repo_change_mode: "direct"
```

Supported values:

- `direct`: commit generated artifacts directly to `env_branch_map[ENV]`.
- `pull_request`: push a feature branch and create or update a Bitbucket pull
  request.

The shared router is:

```text
nativeha_templates/shared_tasks/target_repo_publish.yaml
```

It calls one of:

```text
nativeha_templates/shared_tasks/target_repo_direct_commit.yaml
nativeha_templates/shared_tasks/target_repo_pr.yaml
```

Lab/demo mode:

- Use `target_repo_change_mode: "direct"`.
- No Bitbucket API token or pull request approval is required.
- The playbook commits and pushes directly to `develop` or the configured target
  branch.
- Per-queue-manager `CHANGELOG.md` entries are still written.

Production governance mode:

- Use `target_repo_change_mode: "pull_request"`.
- The playbook creates or updates the stable feature branch
  `feature/<app_prefix>/<qmgr_name>-qmgr`.
- Managers review, approve, and merge the pull request.

This makes the future PR model a configuration switch, not a rewrite.

## Pull Request and Branch Operating Model

When `target_repo_change_mode` is `pull_request`, target repo playbooks must not
push directly to deployment branches such as `develop` or `main`. They must push
automation branches and create or update pull requests.

Automation branch naming:

```text
feature/<app_prefix>/<qmgr_name>-qmgr
```

Examples:

```text
feature/app1/app1q2003-qmgr
feature/app1/app1q2004-qmgr
feature/abc/abcqp001-qmgr
```

Automation-created target repo branches must use the approved `feature/` branch
type. `release/`, `hotfix/`, and `bugfix/` remain available for normal human
source-code release practices, but queue-manager desired-state changes created
by these AAP jobs use `feature/`.

New automation branches must not use action names, timestamps, root changelog
versions, or global semantic versions in the branch name. The branch is a
source-control reservation for one queue manager, not a release identifier. The
`-qmgr` suffix makes that resource ownership explicit.

Lab cleanup rule:

- Only the approved `feature/<app_prefix>/<qmgr_name>-qmgr` branch shape is
  supported by current tested automation.
- Branches from previous experiments should be deleted before testing the next
  iteration.
- The PR helper should not keep compatibility matching for previous lab branch
  naming experiments.

Pull request matching rules:

- An existing open PR may be reused only when the queue manager name matches.
- Matching is based on the source branch prefix:

  ```text
  <app_prefix>/<qmgr_name>-
  ```

- The destination branch must match the configured target branch.
- This intentionally allows multiple approved changes for the same queue
  manager to accumulate in one open PR when that PR is still awaiting review.
- A change for `app1q2003` must never update an open PR for `app1q2002`.
- If no open PR exists, the new PR branch is the stable queue-manager branch
  `feature/app1/<qmgr>-qmgr`, for example `feature/app1/app1q2003-qmgr`.

Create exception:

- `qm_action=Create` should normally allocate the next free sequence and create
  a new queue manager PR.
- If Create resolves to a queue manager that already has an open PR, the job
  must fail clearly instead of reusing that create PR.
- The operator should rerun after project sync, or delete the stale automation
  branch if the pending request was abandoned.

Existing PR branch update flow:

1. List open pull requests through the Bitbucket API.
2. Match only same queue manager and same destination branch.
3. Fetch the existing automation branch.
4. Stash locally generated changes.
5. Check out the existing branch from `refs/remotes/origin/<branch>`.
6. Reapply generated changes.
7. Read the current queue-manager `CHANGELOG.md` from that branch.
8. Write the new changelog entry and PR description.
9. Commit.
10. Rebase against the remote automation branch.
11. Push without force.
12. Update the existing pull request through the API.

Concurrent run behavior:

- If two Create jobs compute the same next queue manager before either one has
  pushed, the first successful push reserves the stable queue-manager branch.
- The second push must fail clearly instead of overwriting the branch. The
  operator should rerun the job after the first run finishes; discovery will then
  see the pending branch and move to the next sequence.
- If two Day-2 jobs target the same queue manager at the same time, only one
  queue-manager branch should win. The other job should fail with a rerun message
  rather than force-pushing.
- If another open same-QMgr PR appears after a job started, the helper must stop
  creating a duplicate PR and remove its own duplicate branch when safe.

If `git status --porcelain` shows no target repo changes before publishing, the
helper should return a no-change result and should not create an empty commit or
empty PR.

Automation changelog path:

```text
<target_repo_pr_repo_path>/CHANGELOG.md
```

The publish helpers may accept an override such as
`target_repo_pr_changelog_path`, but the default must be per queue manager rather
than root `CHANGELOG.md`.

The automation must not use `git push --force` or `git push
--force-with-lease` for normal PR updates. A concurrent update may fail with a
non-fast-forward or merge conflict, but it must not silently overwrite another
job's branch.

If two jobs for the same queue manager update the same files at the same time,
the later job may fail during reapply or rebase. That is acceptable and safer
than overwriting. The operator should rerun after the first PR branch update is
visible.

Publish helper files:

- Router:
  `nativeha_templates/shared_tasks/target_repo_publish.yaml`
- Direct commit helper:
  `nativeha_templates/shared_tasks/target_repo_direct_commit.yaml`
- Active PR backend:
  `nativeha_templates/shared_tasks/target_repo_pr.yaml`

PR backend copies:

- Bitbucket Cloud copy:
  `setup/pr_backends/target_repo_pr_cloud.yaml`
- Bitbucket Data Center/Server copy:
  `setup/pr_backends/target_repo_pr_onprem.yaml`

When the active PR helper changes, keep the backend copy in sync so switching
backends does not introduce drift.

Bitbucket credential expectations:

- Bitbucket Cloud uses `BITBUCKET_USERNAME` plus `BITBUCKET_TOKEN` or
  `BITBUCKET_CLOUD_TOKEN`.
- Bitbucket Data Center/Server uses `BITBUCKET_INTERNAL_TOKEN` or
  `BITBUCKET_TOKEN`, with `BITBUCKET_USERNAME` and `BITBUCKET_PASSWORD` as a
  fallback where supported.
- Tokens must have repository read access and pull request write access.
- The helper should validate API access before attempting to create or update a
  pull request.

## Concurrent Job Operating Model

Users may start AAP jobs simultaneously. The automation must be designed so
parallel jobs are safe by default.

Approved behavior:

- Every run uses an isolated temporary Git work directory under `git_work_dir`.
- Create sequence discovery counts merged queue managers and pending automation
  branches.
- Existing PR branch updates fetch the remote branch before applying new work.
- Pushes are normal non-force pushes.
- If two jobs race before either has pushed a branch, one job may fail at push
  or PR creation time. It must not overwrite the other job.
- The operator reruns the failed job after the winning branch is visible; the
  rerun should then select the next available sequence or update the existing
  queue-manager PR as appropriate.

The automation must prefer visible failure over silent overwrite.

## Manager Approval Model

Normal manager work should be limited to:

- Review the PR title, description, files changed, and queue-manager changelog.
- Approve the PR when the requested change is acceptable.
- Merge the PR into the configured destination branch.

Managers should not need to:

- Edit changelog files manually.
- Resolve root `CHANGELOG.md` conflicts for ordinary queue-manager work.
- Rename automation branches.
- Delete source branches after merge when the provider supports automatic source
  branch cleanup.
- Decide the next queue manager sequence manually.

Manual cleanup is an exception path only. It may be needed when a PR is
intentionally abandoned or declined and the source branch is left behind in the
remote repository.

## Changelog and Manager Review Model

Every automation PR must update the queue-manager changelog when target repo
files changed. The changelog version is scoped to that queue manager and is
parsed from the latest heading using a semantic version search such as:

```text
[0-9]+[.][0-9]+[.][0-9]+
```

Do not parse changelog headings with unsafe bracket-stripping regular
expressions. A heading such as:

```text
## [1.0.3] - 2026-05-06
```

must parse as:

```text
1.0.3
```

Changelog entries and PR descriptions, when PR mode is enabled, must include
enough information for a manager to approve without reconstructing context:

- Action.
- Environment.
- Queue manager.
- Namespace, when available.
- Instance type, when available.
- Size tier, when available.
- Runtime CPU/memory requests and limits, when available.
- Queue manager and log storage, when available.
- Sizing inputs, when available.
- Requested MQ version for image upgrades.
- Requested image for image upgrades.
- License ID for image upgrades.
- Target regions.
- Target path.
- Source branch or direct target branch.
- Whether direct commit mode, a new PR, or an existing open PR was used.
- Human summary.
- Validation performed.
- Reminder that manual approval is required when PR mode is enabled.

The PR helper must normalize optional metadata before templating. Some names,
especially `namespace`, can collide with Jinja built-ins when a Day-2 playbook
does not set a real queue-manager namespace fact. Optional values must be read
through safe local facts such as `_pr_namespace`, `_pr_instance_type`,
`_pr_size_tier`, and `_pr_qmgr_size`.

Root changelog conflict rule:

- Multiple open automation PRs must not all prepend to root `CHANGELOG.md`.
- If one PR is merged before another, a shared root changelog edit will commonly
  conflict even when the actual queue-manager files are clean.
- The PR helper should restore root `CHANGELOG.md` from the base branch in
  pull-request mode and write automation history under the queue-manager path.
- Direct mode should not write root `CHANGELOG.md`; it should write only the
  per-queue-manager changelog.
- Queue-manager changelog versions are local to each queue manager. Two
  different queue managers can both have changelog entry `1.0.1` or `1.0.2`
  without creating a source-control conflict.
- New branch names must not include those changelog versions. The conflict risk
  came from editing the same shared root file, not from two queue managers having
  the same local changelog number.

## GitOps Boundary

Default automation behavior:

- Generate artifacts.
- Publish artifacts through `target_repo_change_mode`.
- In direct mode, commit and push directly to the configured environment branch.
- In pull request mode, commit artifacts to feature branches and create or update
  pull requests targeting the configured environment branch.
- In pull request mode, request source branch cleanup on merge where the Git
  provider supports it.
- Verify artifacts locally where appropriate.

Default automation must not:

- Run `oc apply`.
- Delete OpenShift resources.
- Delete PVCs.
- Force ArgoCD refresh.
- Create ArgoCD Applications in the cluster.
- Call ArgoCD CLI/API.
- Query OpenShift from playbooks for state discovery.
- Force-push over a branch that another automation job may have updated.

Allowed verification:

- `ansible-playbook --syntax-check`
- `git diff --check`
- Clone target repo read-only.
- Inspect generated YAML.
- Run local `kubectl kustomize` against generated overlays.
- Check local registry tags.
- Use read-only `oc get`, `oc describe`, and `oc logs` only when investigating a
  cluster issue and the user has asked for cluster analysis.

## Base + Overlays Model

`base/qmgr.yaml` is a structural skeleton. It is not always the final deployable
truth for fields intentionally controlled by overlays.

The deployable truth is:

```bash
kubectl kustomize queue_managers/<ENV>/<qmgr_name>/overlays/<region>
```

The target repo uses regional overlays because CRR queue managers need
region-specific identity and role values.

## Base Placeholder Rules

`base/qmgr.yaml` can contain placeholders for fields intentionally controlled by
Day-2 overlays.

Current placeholders:

```yaml
spec:
  version: PLACEHOLDER_MQ_VERSION
  license:
    accept: true
    license: PLACEHOLDER_LICENSE_ID
  queueManager:
    image: PLACEHOLDER_MQ_IMAGE
```

CRR placeholders:

```text
PLACEHOLDER_REGION
PLACEHOLDER_ROLE
PLACEHOLDER_REMOTE
PLACEHOLDER_ADDRESS
```

These values are resolved by overlay patches.

## License Use Ownership

`spec.license.use` is not owned by image update.

It is an onboarding-time environment decision:

```text
PROD     -> Production
non-PROD -> NonProduction
```

Therefore, `base/qmgr.yaml` should contain:

```yaml
spec:
  license:
    use: Production
```

or:

```yaml
spec:
  license:
    use: NonProduction
```

depending on the environment.

The image upgrade playbook must not patch:

```text
/spec/license/use
```

## Image Patch Ownership

`qm-image-patch.yaml` patches only:

```text
/spec/version
/spec/license/license
/spec/queueManager/image
```

It must not patch:

```text
/spec/license/use
```

Example:

```yaml
---
# qm-image-patch.yaml — JSON 6902 patch for MQ version/license ID/image update
- op: replace
  path: /spec/version
  value: "9.4.4.1-r1"
- op: replace
  path: /spec/license/license
  value: "L-DUMMY-LICENSE-NONPROD"
- op: replace
  path: /spec/queueManager/image
  value: "services.example.lab:5000/ibm-mq/mq:9.4.4.1-r1"
```

## Image Upgrade Workflow

Current inputs:

```text
app_sys_id=<app id>
mq_environment=<DEV|QA1|QA2|QA3|PROD>
qmgr_name=<single|comma-separated-list|all>
new_mq_version=<target MQ image tag>
new_license_id=<optional override>
```

`qmgr_name` values:

```text
app1q2001
app1q2001,app1q2002
all
```

When `qmgr_name=all`, automation updates all queue managers in the target
environment whose names start with:

```text
<app_sys_id><env_qmgr_abbr>
```

Current behavior:

1. Validate inputs.
2. Validate selected queue manager names belong to the supplied `app_sys_id`
   and `mq_environment`.
3. Clone target repo and branch.
4. Resolve the selected queue manager set from the Git-backed target repo.
5. Locate discovered image patches:

   ```text
   queue_managers/<ENV>/<qmgr_name>/overlays/*/qm-image-patch.yaml
   ```

6. Render each discovered `qm-image-patch.yaml`.
7. Assert that only discovered image patch files changed before changelog
   metadata is added.
8. Publish through the configured target repo change mode if changes exist.
9. Clean temporary working directory.

Current example:

```bash
ansible-playbook NativeHA_Image_Upgrade/playbooks/NativeHA_Image_Upgrade.yaml \
  -e 'app_sys_id=app1 mq_environment=QA2 qmgr_name=all new_mq_version=9.4.4.1-r1'
```

Expected result:

```text
queue_managers/QA2/app1q2001/overlays/cluster1/qm-image-patch.yaml
queue_managers/QA2/app1q2001/overlays/cluster2/qm-image-patch.yaml
```

both point to:

```text
services.example.lab:5000/ibm-mq/mq:9.4.4.1-r1
```

## Role Switch Workflow

Current inputs:

```text
qmgr_name=<qmgr name>
mq_environment=<QA2|PROD>
new_live_region=<region key>
```

Current behavior:

1. Validate inputs.
2. Validate that the queue manager name belongs to the supplied environment.
3. Validate that role switching is used only for CRR environments, currently
   QA2 and PROD.
4. Validate that `new_live_region` is one of the configured `regions` keys.
5. Clone the target repo and branch.
6. Locate existing regional role patch files.
7. Update only the regional role patch values.
8. Validate rendered role values.
9. Assert that only expected role patch files changed before changelog updates.
10. Publish through the configured target repo change mode.
11. Clean the temporary working directory.

Role switch is staged:

- `noop` when the requested live region is already live.
- `stage1_demote` when the current live region must first be moved away from
  `Live`.
- `stage2_promote` when the requested live region can be promoted to `Live`.

Role switch must not:

- Modify queue manager base manifests.
- Modify image upgrade patch files.
- Query OpenShift for role discovery.
- Call ArgoCD or force cluster synchronization.

The role switch source of truth is the Git-backed overlay patch state.

## Certificate Lifecycle Workflow

Certificate management is separate from queue manager onboarding but must derive
the same identity. The certificate workflow uses:

```text
app_prefix=<3-character application id>
mq_environment=<DEV|QA1|QA2|QA3|PROD>
sequence_number=<3-digit sequence>
instance_type=<single|nha|nhacrr>
cert_action=<onboard|offboard|monitor>
```

Identity derivation must produce the same:

- `qmgr_name`
- `namespace`
- Vault security zone
- Vault namespace and mount

Certificate responsibilities:

- Generate/request the cert types required by `instance_type`.
- Store certificate material in the configured Vault KV path.
- Keep Vault path conventions aligned with VSO `VaultStaticSecret` templates.
- Update the Git-backed certificate registry.
- Support monitor flows for one queue manager or all queue managers from the
  registry.
- Support offboard flows that revoke or mark certificates and purge Vault data
  only through explicit certificate offboarding logic.

Certificate state rules:

- The certificate registry is Git-backed and currently uses `cert_git_branch`.
- Certificate registry updates must use normal Git commits.
- PROD must not skip Vault interactions.
- Queue manager and certificate code must not drift in naming logic.

## License ID Derivation

The user should not normally provide `license_id` or `license_use`.

User provides:

```text
app_sys_id
qmgr_name
mq_environment
new_mq_version
```

Automation derives:

- `license_use` from existing `base/qmgr.yaml` or environment.
- `license_id` from configured license policy/matrix.
- `image` from registry/repository/version.

Current simple mapping:

```yaml
license_ids:
  NONPROD: "L-DUMMY-LICENSE-NONPROD"
  PROD: "L-DUMMY-LICENSE-PROD"
```

Recommended future mapping:

```yaml
mq_license_policy: mq_advanced

mq_license_matrix:
  mq_advanced:
    "9.4":
      Production: "L-NUUP-23NH8Y"
      NonProduction: "L-DUMMY-LICENSE-NONPROD"
  cp4i:
    "9.4":
      Production: "L-DUMMY-LICENSE-PROD"
      NonProduction: "L-DUMMY-LICENSE-PROD"
```

Reason:

IBM MQ has multiple valid license IDs for the same MQ version and license use.
The missing decision is the entitlement policy, not the image tag alone.

## Internal Registry

Local registry endpoint:

```text
services.example.lab:5000
```

MQ image repository:

```text
services.example.lab:5000/ibm-mq/mq
```

Current test tags:

```text
9.4.3.1-r1
9.4.4.0-r1
9.4.4.1-r1
9.4.5.0-r2
```

Current non-prod onboarding default:

```yaml
mq_versions:
  NONPROD: "9.4.3.1-r1"
```

Registry container:

```text
local-registry
```

Systemd user unit:

```text
/home/appuser/.config/systemd/user/container-local-registry.service
```

The registry was recreated with deletion support:

```text
REGISTRY_STORAGE_DELETE_ENABLED=true
```

This allows obsolete tags to be removed using the registry API.

Useful registry checks:

```bash
curl -fsS http://services.example.lab:5000/v2/
curl -fsS http://services.example.lab:5000/v2/ibm-mq/mq/tags/list
systemctl --user is-active container-local-registry.service
systemctl --user is-enabled container-local-registry.service
```

Useful mirror command:

```bash
skopeo copy --dest-tls-verify=false \
  docker://icr.io/ibm-messaging/mq:<tag> \
  docker://services.example.lab:5000/ibm-mq/mq:<tag>
```

## Important OpenShift Finding: Reused PVCs Can Break Older MQ Starts

Observed scenario:

1. `APP1Q2001` was previously deployed with MQ `9.4.5.0`.
2. Later, target repo generated `APP1Q2001` again with MQ `9.4.3.1-r1`.
3. OpenShift still had old PVCs for `APP1Q2001`.
4. The new deployment reused old queue manager data/log volumes.
5. MQ `9.4.3.1` failed to start the queue manager because the data had already
   been started by a newer MQ level.

Observed MQ error:

```text
AMQ7204E: IBM MQ queue manager 'APP1Q2001' cannot be started or otherwise administered by this installation.
It has previously been started by a newer release of IBM MQ.
```

Observed PVCs:

```text
data-app1q2001-ibm-mq-0
data-app1q2001-ibm-mq-1
data-app1q2001-ibm-mq-2
recovery-logs-app1q2001-ibm-mq-0
recovery-logs-app1q2001-ibm-mq-1
recovery-logs-app1q2001-ibm-mq-2
```

Root cause:

The queue manager persistent data was already migrated/used by a newer MQ
command level. A lower MQ image cannot simply start that data.

Conclusion:

To test a queue manager starting from an older version:

- Use a truly new queue manager name/namespace/sequence, or
- Fully remove old queue manager resources and PVCs before recreating the same
  name.

Do not treat this as a valid rollback test.

## Rollback Principles

Rollback must be GitOps-based.

Do not rely on ArgoCD CLI rollback for normal operation, especially when
automated sync is enabled. The safe GitOps rollback model is a new Git commit
that restores previous `qm-image-patch.yaml` values.

### Safe Automated Rollback

Automated rollback is allowed only within the same MQ VRMF when only the image
revision changes.

Example:

```text
9.4.5.0-r2 -> 9.4.5.0-r1
```

### Unsafe Automated Rollback

Automatic rollback must be blocked across VRMF or command-level boundaries.

Examples:

```text
9.4.5.0-r2 -> 9.4.4.1-r1
9.4.x      -> 9.3.x
```

Reason:

After a queue manager starts on a newer MQ level, its data may not be
startable/administerable by an older MQ release.

### Version Parsing

Example:

```text
9.4.5.0-r2
```

Parsed as:

```text
major        = 9
minor        = 4
modification = 5
fix          = 0
revision     = r2
```

Automated rollback is allowed only if:

- `major.minor.modification.fix` are identical.
- only `revision` changes.

Cross-VRM rollback should fail and direct the operator to a break-glass runbook.

## Break-Glass Rollback

Break-glass rollback is not a simple image tag change.

It should require one of:

- Restore from pre-upgrade backups/snapshots.
- Recreate a replacement queue manager from known-good data.
- Follow an IBM MQ documented recovery/migration procedure.

The image upgrade playbook should not automatically mutate Git for cross-VRM
rollback. It should fail clearly and explain the risk.

## Recommended Rollback Metadata

Future image upgrade should store enough Git metadata to support rollback.

Recommended artifact:

```text
queue_managers/<ENV>/<qmgr_name>/overlays/.upgrade-history.yaml
```

or a central history file:

```text
queue_managers/<ENV>/<qmgr_name>/upgrade-history.yaml
```

Suggested fields:

```yaml
history:
  - timestamp: "2026-05-05T00:00:00Z"
    action: upgrade
    qmgr_name: app1q2001
    environment: QA2
    previous_version: 9.4.3.1-r1
    new_version: 9.4.4.1-r1
    previous_image: services.example.lab:5000/ibm-mq/mq:9.4.3.1-r1
    new_image: services.example.lab:5000/ibm-mq/mq:9.4.4.1-r1
    previous_license_id: L-DUMMY-LICENSE-NONPROD
    new_license_id: L-DUMMY-LICENSE-NONPROD
    license_use: NonProduction
    git_commit: <commit>
    changed_by: ansible
```

## Ansible Implementation Rules

Use:

- Fully qualified module names.
- Isolated temporary Git work directories per run.
- `always` blocks for cleanup.
- `check_mode: false` for clone/cleanup tasks that must run even in check mode.
- Existing repo patterns and variables.

Do not:

- Query OpenShift from playbooks for discovery.
- Put Day-2 upgrade/role-switch workflows under queue manager onboarding.
- Hardcode environment-specific values outside `nativeha_templates/global_vars/`.
- Use ad hoc shell parsing where Ansible/YAML structured operations are more
  appropriate.

## Current Important Files

```text
nativeha_templates/global_vars/nativeha_qmgr_control_vars.yaml
nativeha_templates/base/qmgr_templates/crr_qmgr.yaml.j2
nativeha_templates/base/qmgr_templates/nha_qmgr.yaml.j2
nativeha_templates/base/qmgr_templates/sgl_qmgr.yaml.j2
nativeha_templates/overlays/qm_image_patch.yaml.j2
nativeha_templates/shared_tasks/target_repo_publish.yaml
nativeha_templates/shared_tasks/target_repo_direct_commit.yaml
nativeha_templates/shared_tasks/target_repo_pr.yaml
NativeHA_Qmgr_Automate_Deployment/playbooks/NativeHA_Qmgr_Onboard.yaml
NativeHA_Qmgr_Automate_Deployment/roles/qmgr_onboard/tasks/main.yaml
NativeHA_Qmgr_Automate_Deployment/roles/qmgr_onboard/tasks/workflow.yaml
NativeHA_Qmgr_Automate_Deployment/roles/qmgr_onboard/tasks/discover_sequence.yaml
NativeHA_Qmgr_Automate_Deployment/roles/qmgr_onboard/tasks/generate_overlay.yaml
NativeHA_Qmgr_Automate_Deployment/roles/qmgr_onboard/tasks/git_operations.yaml
setup/pr_backends/target_repo_pr_cloud.yaml
setup/pr_backends/target_repo_pr_onprem.yaml
NativeHA_Image_Upgrade/playbooks/NativeHA_Image_Upgrade.yaml
NativeHA_Image_Upgrade/roles/nativeha_image_upgrade/tasks/main.yaml
NativeHA_Role_Switch/playbooks/NativeHA_Role_Switch.yaml
NativeHA_Role_Switch/roles/role_switch/tasks/main.yaml
NativeHA_Cert_Management/playbooks/NativeHA_Cert_Management.yaml
NativeHA_Cert_Management/roles/cert_common/tasks/derive_identity.yaml
NativeHA_Cert_Management/roles/cert_common/tasks/update_registry.yaml
docs/crr-base-overlays-rationale.md
docs/local-registry-permanent-fix.md
docs/mq-version-licensing-guide.md
```

## Standard Verification Commands

Syntax check onboarding:

```bash
ansible-playbook --syntax-check \
  NativeHA_Qmgr_Automate_Deployment/playbooks/NativeHA_Qmgr_Onboard.yaml
```

Syntax check image upgrade:

```bash
ansible-playbook --syntax-check \
  NativeHA_Image_Upgrade/playbooks/NativeHA_Image_Upgrade.yaml
```

Syntax check role switch:

```bash
ansible-playbook --syntax-check \
  NativeHA_Role_Switch/playbooks/NativeHA_Role_Switch.yaml
```

Lint the primary playbooks:

```bash
ansible-lint \
  NativeHA_Qmgr_Automate_Deployment/playbooks/NativeHA_Qmgr_Onboard.yaml \
  NativeHA_Image_Upgrade/playbooks/NativeHA_Image_Upgrade.yaml \
  NativeHA_Role_Switch/playbooks/NativeHA_Role_Switch.yaml
```

Whitespace check:

```bash
git diff --check
```

Confirm active Cloud PR helper and backend copy are in sync:

```bash
cmp -s nativeha_templates/shared_tasks/target_repo_pr.yaml \
  setup/pr_backends/target_repo_pr_cloud.yaml
```

Registry tag check:

```bash
curl -fsS http://services.example.lab:5000/v2/ibm-mq/mq/tags/list
```

Render target repo overlays:

```bash
kubectl kustomize queue_managers/QA2/app1q2001/overlays/cluster1
kubectl kustomize queue_managers/QA2/app1q2001/overlays/cluster2
```

Check rendered version/image/license:

```bash
kubectl kustomize queue_managers/QA2/app1q2001/overlays/cluster1 | \
  rg 'version:|image:|license:|use:|role:'
```

## Example Onboarding Run

```bash
ansible-playbook \
  NativeHA_Qmgr_Automate_Deployment/playbooks/NativeHA_Qmgr_Onboard.yaml \
  -e 'qm_action=create app_sys_id=app1 mq_environment=QA2 total_volume_24h=1m avg_msg_size=1k'
```

Expected result:

- Queue manager artifacts generated under:

  ```text
  queue_managers/QA2/app1q2001/
  ```

- Base contains:

  ```yaml
  use: NonProduction
  ```

- Overlay image patch contains current non-prod default:

  ```text
  9.4.3.1-r1
  ```

- Automation branch and PR are created, for example:

  ```text
  feature/app1/app1q2001-qmgr -> develop
  ```

## Example Image Upgrade Run

```bash
ansible-playbook \
  NativeHA_Image_Upgrade/playbooks/NativeHA_Image_Upgrade.yaml \
  -e 'app_sys_id=app1 mq_environment=QA2 qmgr_name=app1q2001 new_mq_version=9.4.4.1-r1'
```

Expected result:

```text
queue_managers/QA2/app1q2001/overlays/cluster1/qm-image-patch.yaml
queue_managers/QA2/app1q2001/overlays/cluster2/qm-image-patch.yaml
```

contain:

```text
9.4.4.1-r1
services.example.lab:5000/ibm-mq/mq:9.4.4.1-r1
```

and do not contain:

```text
/spec/license/use
```

The image upgrade should create or update an automation PR, for example:

```text
feature/app1/app1q2001-qmgr -> develop
```

## Operational Lessons Learned

### `dspmqver` and Image Revisions

Upgrading:

```text
9.4.5.0-r1 -> 9.4.5.0-r2
```

may not change `dspmqver` output because both images can contain the same MQ
product VRMF:

```text
Version: 9.4.5.0
MaxCmdLevel: 945
```

The reliable proof is the pod image digest and QueueManager reconciled version:

```bash
oc get qmgr app1q2001 -n app1-mq-qa2-001 \
  -o jsonpath='{.status.versions.reconciled}{"\n"}'

oc get pod app1q2001-ibm-mq-0 -n app1-mq-qa2-001 \
  -o jsonpath='{.status.containerStatuses[?(@.name=="qmgr")].imageID}{"\n"}'
```

### Prometheus Exporter Authorization

Observed exporter error:

```text
MQRC_NOT_AUTHORIZED [2035]
AMQ9777E: Channel was blocked
```

Root cause:

The monitoring channel existed and `mqmon` AUTHREC grants existed, but CHLAUTH
blocked the SVRCONN before AUTHREC was evaluated.

Permanent MQSC rule:

```mqsc
SET CHLAUTH('MONITOR.SVRCONN') TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(CHANNEL) ACTION(REPLACE)
```

This belongs in the shared base MQSC so future queue managers are generated with
the fix.

## Final Guardrails

Plan phase:

- Analyze repo and requirements.
- Explain proposed changes.
- Do not edit files until plan is approved.

Implementation phase:

- Make scoped changes.
- Avoid unrelated refactors.
- Run syntax checks.
- Run `git diff --check`.
- Verify rendered overlays locally.
- Summarize changes and verification.

Operational mutation:

- Do not mutate OpenShift or ArgoCD unless explicitly requested.
- Prefer artifact-only changes.
- If cluster investigation is requested, start read-only.


## Recent Architectural Updates & Dynamic Capabilities

The automation suite has matured to include several advanced dynamic behaviors to adhere to strict GitOps and D.R.Y (Don't Repeat Yourself) principles:

### Shared Task Library
- **Centralized Logic:** `nativeha_templates/shared_tasks/` now consolidates logic for Git cloning, configuration, target repo publishing (direct commit vs. pull request), and Bitbucket API interaction.
- All playbooks (Onboarding, Cert Management, Image Upgrade, Role Switch) dynamically invoke these shared tasks via relative paths (e.g., `../../../../nativeha_templates/shared_tasks/target_repo_publish.yaml`).

### Dynamic Sizing & Discovery
- **Sizing Logic:** Message volume computation intelligently handles SI string multipliers (e.g., `1k`, `1m`) via the custom `mq_sizing.py` filter plugin to avoid confusing string literal '1m' with binary storage size '1Mi'.
- **Sequence Increments:** Greenfield onboarding discovers queue manager sequences dynamically. To prevent collisions, atomic `set_fact` sequences merge logic to cross-reference both merged base directories (`queue_managers/`) and pending target repo pull request branches (`feature/<app>/<qmgr>-qmgr`).

### Symmetrical Base + Overlays
- **Immutable Base:** The base templates (`nativeha_templates/base/`) no longer leak environment-specific variables like `_target_region`. 
- **Identity via Overlays:** Day-2 workflows (Role Switch and Image Upgrade) rely exclusively on Kustomize `overlays/<region>/` patching. The overlay injects the regional identity (labels, remote CRR addresses, specific roles, version bumps) leaving base artifacts pristine.

### PKI Automation
- **Vault Secrets Operator (VSO):** Dynamic generation of Vault static secret manifestations allows VSO to automatically orchestrate and rotate mTLS/TLS materials directly from Vault KV v2 paths.

## Technical Challenges Faced & Resolutions

1. **Jinja2 Regex Escaping in YAML Block Scalars (`>-`):**
   - **Challenge:** Git status parsing tasks using `regex_replace` inside folded block scalars (`>-`) were failing. In this specific YAML format, backslashes are evaluated literally. Double-escaping (e.g., `\s`, `\1`) caused regex to evaluate a literal backslash plus the character, breaking the regex.
   - **Resolution:** Stripped double backslashes in favor of precise single backslashes (`\s`, ``) strictly inside `>-` blocks.
2. **Bitbucket Cloud API Authentication:**
   - **Challenge:** Executing Pull Requests via REST API returned 401/403 authorization failures across on-prem and cloud endpoints.
   - **Resolution:** Standardized dynamic Basic Authentication combining `BITBUCKET_USERNAME` and token strings into base64 format for safe header injection across different backends (`target_repo_pr.yaml`).

## SRE Execution Instructions & Maintenance Notes

- **AAP Project Sync:** Whenever structural changes are made to `nativeha_templates/shared_tasks/` or `nativeha_qmgr_control_vars.yaml`, SRE operators *must* trigger a project sync within AAP before executing any job template to ensure execution nodes pull the latest definitions.
- **Includes Pathing:** When writing new playbook logic requiring shared routines, the `ansible.builtin.include_tasks` instruction must utilize the `../../../../nativeha_templates/` relative path traversal from the role's `tasks/` directory, rather than relying on `playbook_dir` derivations.
- **Environment Context:** Validate that `BITBUCKET_USERNAME`, `BITBUCKET_TOKEN` (or `BITBUCKET_CLOUD_TOKEN`), and `VAULT_TOKEN` are securely exported to the execution container prior to kickoff.
