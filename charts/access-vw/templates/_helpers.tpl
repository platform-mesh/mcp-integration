{{- define "access-vw.labels" -}}
app: access-vw
app.kubernetes.io/name: access-vw
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Prefix for per-cluster endpoints in SCAR responses: explicit value or
built from the external front-proxy address.
*/}}
{{- define "access-vw.endpointBase" -}}
{{ .Values.server.endpointBase | default (printf "https://%s:%v/clusters/" .Values.external.hostname .Values.external.port) }}
{{- end }}
