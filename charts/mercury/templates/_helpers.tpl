{{- define "mercury.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mercury.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "mercury.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
app.kubernetes.io/name: {{ include "mercury.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mercury
{{- end -}}

{{- define "mercury.selector" -}}
app.kubernetes.io/name: {{ include "mercury.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "mercury.secretName" -}}
{{- default (include "mercury.fullname" .) .Values.secrets.existingSecret -}}
{{- end -}}

{{- define "mercury.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "mercury.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "mercury.gatewayName" -}}
{{ include "mercury.fullname" . }}-gateway
{{- end -}}

{{- define "mercury.dbName" -}}
{{ include "mercury.fullname" . }}-gateway-db
{{- end -}}

{{- define "mercury.controllerTag" -}}
{{- default .Chart.AppVersion .Values.image.controller.tag -}}
{{- end -}}

{{- define "mercury.sandboxImage" -}}
{{ .Values.image.sandbox.repository }}:{{ default .Chart.AppVersion .Values.image.sandbox.tag }}
{{- end -}}

{{/* An env entry that reads one key from the secret, tolerating its absence. */}}
{{- define "mercury.secretEnv" -}}
- name: {{ .key }}
  valueFrom:
    secretKeyRef:
      name: {{ .secret }}
      key: {{ .key }}
      optional: true
{{- end -}}
