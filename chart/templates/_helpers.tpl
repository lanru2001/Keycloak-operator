{{/*
Chart name and version label.
*/}}
{{- define "keycloak-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all operator resources.
*/}}
{{- define "keycloak-operator.labels" -}}
helm.sh/chart: {{ include "keycloak-operator.chart" . }}
app.kubernetes.io/name: keycloak-operator
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels for the operator Deployment / Service.
The operator pods carry only `app.kubernetes.io/name` as the selector key (matches upstream).
*/}}
{{- define "keycloak-operator.selectorLabels" -}}
app.kubernetes.io/name: keycloak-operator
{{- end }}

{{/*
Labels for the bundled in-cluster Postgres StatefulSet.
*/}}
{{- define "keycloak-operator.postgresLabels" -}}
helm.sh/chart: {{ include "keycloak-operator.chart" . }}
app.kubernetes.io/name: postgres
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "keycloak-operator.postgresSelectorLabels" -}}
app: postgres
{{- end }}

{{/*
Effective K8s Secret name holding the bootstrap admin credentials.
The Secret is referenced consistently by:
  - bootstrap-admin-secret.yaml  (renders the Secret when bootstrapAdmin.password is set)
  - keycloak.yaml                (Keycloak CR's spec.bootstrapAdmin.user.secret)
  - realm-config-cli-job.yaml    (config-cli's admin credentials)
Customers using an external provider (ExternalSecret, Vault, etc.) must
provision a Secret with this exact name; plaintext customers just set
bootstrapAdmin.password and the chart renders it.
*/}}
{{- define "keycloak-operator.bootstrapAdminSecretName" -}}
{{- .Values.keycloak.bootstrapAdmin.secretName | default (printf "%s-bootstrap-admin" .Release.Name) -}}
{{- end }}
