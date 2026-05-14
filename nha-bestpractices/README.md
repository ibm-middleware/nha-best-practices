# NativeHA MQ Management

This directory is the Ansible entrypoint for IBM MQ NativeHA lifecycle
automation.

## Layout

```text
playbooks/
  qmgr/    # Day 1 onboarding; Day 2 app MQSC, sizing, image, role, restart
  certs/   # cert onboard, renew, monitor, offboard, diagnostics, trust add

roles/
  qmgr_*         # queue-manager GitOps lifecycle roles
  cert_*         # certificate lifecycle roles
  gitops_publish # shared target-repo publish role for GitOps workflows
```

## Operating Rules

- Keep separate AAP job templates for each playbook.
- Prefix AAP job templates with `Day 1 -` for initial provisioning and
  `Day 2 -` for operational changes.
- Attach only the credentials required by that job template.
- Keep queue-manager GitOps changes in target repos through `gitops_publish`.
- Keep Day-2 queue-manager sizing changes in
  `overlays/_shared/patches/qm-sizing-patch.yaml`; do not rewrite
  `base/qmgr.yaml` for sizing updates.
- Deploy application-owned MQ objects through
  `NativeHA_App_Objects_Deploy.yaml`, which updates app MQSC and, by default,
  restart patches in the same GitOps change.
- Trigger planned queue manager restarts by updating regional restart patches,
  not by deleting pods directly from Ansible.
- Keep certificate material in OpenShift Secrets or Vault, never in Git.
- Keep certificate inventory metadata only on the dedicated registry branch,
  under `nativeha_state/cert_registry/`; do not keep `nativeha_state/` on
  main/master.
- Keep client/signer mutual-TLS trust in the dedicated `<qmgr>-client-certs`
  Secret and GitOps trust patch. In VSO mode, keep the public PEM source in
  shared Vault and let VSO sync the Secret; do not append it to Venafi identity
  Secrets.
