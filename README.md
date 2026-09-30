# Keycloak Operator

This folder contains the Keycloak Operator Helm chart and base configuration for
deploying Keycloak as the Lasso platform identity provider (OIDC). Keycloak is the
**self-hosted** alternative to a managed cloud IdP (AWS Cognito / Azure Entra) — choose
it for air-gapped or fully self-contained deployments, or when you want to federate
your own SAML IdP behind a single OIDC issuer you control.

> **Customization**: see [`docs/examples/keycloak-operator/`](../../docs/examples/keycloak-operator/README.md)
> for a fill-in-the-blanks deployment overlay (database, secrets, realm, identity providers).
> For the full end-to-end setup flow (database → overlay → deploy → platform wiring → verify),
> see [`docs/KEYCLOAK_SETUP.md`](../../docs/KEYCLOAK_SETUP.md).

## Directory Structure

```
apps/keycloak-operator/
├── chart/                    # Keycloak Operator Helm chart
│   ├── Chart.yaml
│   ├── crds/                 # Keycloak + KeycloakRealmImport CRDs
│   ├── templates/            # Operator, Keycloak CR, in-cluster Postgres, realm reconciler
│   └── values.yaml           # Full chart defaults (every value documented inline)
├── values.yaml               # Base recommended values (common to all deployments)
└── README.md
```

## Prerequisites

1. **Kubernetes**: EKS 1.27+ (or compatible), with an ingress controller (ALB / NGINX) for external access.
2. **kubectl** + **Helm** v3.10+.
3. **A PostgreSQL database** — managed (RDS / Azure DB / Cloud SQL), or the bundled in-cluster Postgres (Option B below).
4. **DNS + TLS** for the public Keycloak hostname (`${KEYCLOAK_HOST}`, e.g. `auth.customer.com`).

## Database: pick ONE option

The chart defaults to **external managed Postgres (RDS)**. The bundled in-cluster
Postgres is opt-in.

| Option | When | How |
|--------|------|-----|
| **A — Managed Postgres / RDS** (default) | Production; you already run managed Postgres | `postgres.enabled: false` (default) + set `keycloak.db.host` / `url` / `username` and the DB password |
| **B — In-cluster Postgres** | Quick start / no managed DB available | `postgres.enabled: true` + `keycloak.db.host: postgres`. Data lives on a PVC — ensure a backup story |

See [`docs/examples/keycloak-operator/values.yaml`](../../docs/examples/keycloak-operator/values.yaml) —
Option A is active, Option B is included commented-out.

## Secrets: plaintext (default) vs External Secrets

The chart is **ship-ready without External Secrets Operator** — provide secrets as
plain text and the chart renders the K8s Secrets inline:

- **DB credentials**: `keycloak.db.credentialsSecret.create: true` + `password: "${DB_PASSWORD}"`.
- **Bootstrap admin**: `keycloak.bootstrapAdmin.password: "${KEYCLOAK_ADMIN_PASSWORD}"`.

> Store the filled values file securely (secret manager / sealed git) and rotate
> credentials per your policy.

If you **do** run External Secrets Operator / Vault, set `create: false` on
`credentialsSecret`, point `bootstrapAdmin.secretName` at a pre-provisioned Secret,
and add your `ExternalSecret` manifests under `extraResources`.

## Quick Start

```bash
# 1. Fill in the example overlay — replace every ${...} placeholder
$EDITOR docs/examples/keycloak-operator/values.yaml

# 2. Install (base values + the overlay)
helm upgrade --install keycloak apps/keycloak-operator/chart \
  -n keycloak --create-namespace \
  -f apps/keycloak-operator/values.yaml \
  -f docs/examples/keycloak-operator/values.yaml
```

The chart's `crds/` (Keycloak + RealmImport) are large; if a client-side apply hits
the annotation size limit, apply them server-side first:

```bash
kubectl apply --server-side --force-conflicts -f apps/keycloak-operator/chart/crds/
```

The `${...}` placeholders are documented in the
[example overlay README](../../docs/examples/keycloak-operator/README.md#placeholders-to-replace).

## Realm Management

The realm is defined once under `realms:` in the values and applied through two
mechanisms that work together:

- **`KeycloakRealmImport`** (operator CRD) — creates the realm on first install.
  It is import-once: the operator never updates an existing realm from it.
- **`keycloak-config-cli` Job** (post-install / post-upgrade hook, or ArgoCD PostSync) —
  reconciles the `realms:` spec into the running realm on **every** `helm upgrade` /
  sync. This is how realm changes (new IdPs, client tweaks) reach an existing deployment.

So to change realm config: edit your overlay, run `helm upgrade`, and check the
`realm-config-cli` Job completed. Manual changes made in the Keycloak admin console
are overwritten on the next sync.

> **The reconciler is gated.** The `keycloak-config-cli` Job only renders when
> `realmConfigCli.enabled: true` **and** at least one `realms:` entry exists —
> otherwise it is **silently skipped** and realm changes never apply. The base
> `values.yaml` sets `realmConfigCli.enabled: true`, but the **chart default is
> `false`**, so the Job runs only when you deploy with the base values
> (`-f apps/keycloak-operator/values.yaml`), not the chart on its own.

### Reconciler options (`realmConfigCli`)

Tunable in your overlay; every field is documented inline in
[`chart/values.yaml`](chart/values.yaml):

| Field | Default | Notes |
|:------|:--------|:------|
| `realmConfigCli.enabled` | `true` in base `values.yaml` (chart default `false`) | Master switch for the reconciler Job. |
| `realmConfigCli.managed.*` (`client`, `identityProvider`, `identityProviderMapper`, `authenticationFlow`) | `no-delete` | `no-delete` is additive/update-only — **removing an IdP or client from the overlay does NOT delete it from the live realm**. Switch to `full` to let the Job prune resources absent from the YAML (once you trust the YAML is authoritative). |
| `realmConfigCli.image.tag` | `<cli-version>-<keycloak-version>` | Keep the Keycloak suffix in sync with the operator's Keycloak image — matters when mirroring images for air-gapped installs. |

## Configurable Realm Parameters

The base `values.yaml` ships the full Lasso realm. Most settings are required and
should not be changed. The following parameters can be adjusted per deployment
(override in your overlay):

| Parameter | Default | Description |
|:----------|:--------|:------------|
| `sslRequired` | `external` | Require HTTPS externally; allow HTTP for private/localhost |
| `ssoSessionIdleTimeout` | `2592000` (30 days) | How long a session stays alive without activity |
| `ssoSessionMaxLifespan` | `2592000` (30 days) | Maximum session duration regardless of activity |
| `accessTokenLifespan` | `3600` (60 min) | Access token validity. Frontend silently refreshes before expiry |
| `accessCodeLifespanLogin` | `180` (3 min) | Time to complete the full login flow |
| `redirectUris` / `webOrigins` | `${DASHBOARD_URL}` | Dashboard FQDN for client redirect URIs and CORS |

## How Auth Fits Together

1. The dashboard redirects the user to Keycloak (optionally with `kc_idp_hint`).
2. Keycloak federates to the customer IdP (SAML) and issues tokens.
3. The dashboard sends the id_token to the backend (`POST /acl/v1/auth/session`).
4. The backend (`IDP_STRATEGY=OIDC`, `AUTHORITY_URL=https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}`)
   validates the JWT via the realm's JWKS and creates/links the user.

> The realm id must match `AUTHORITY_URL` / `VITE_IDP_AUTHORITY` configured on the
> server + dashboard: `https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}`. The SPA
> client id is `lasso-platform` (matches `VITE_IDP_CLIENT_ID`).

## See Also

- [`docs/KEYCLOAK_SETUP.md`](../../docs/KEYCLOAK_SETUP.md) — end-to-end setup guide (DB → overlay → deploy → platform wiring → verify)
- [`docs/examples/keycloak-operator/`](../../docs/examples/keycloak-operator/README.md) — fill-in-the-blanks deployment overlay + placeholder guide
- [`chart/values.yaml`](chart/values.yaml) — every chart value documented inline
- [`DEPLOYMENT_GUIDE.md`](../../DEPLOYMENT_GUIDE.md) — full platform deployment documentation
