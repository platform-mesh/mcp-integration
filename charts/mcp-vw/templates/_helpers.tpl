{{/*
Image reference: registry/repository:tag (tag defaults to appVersion).
*/}}
{{- define "mcp-vw.image" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "mcp-vw.labels" -}}
app: mcp-vw
app.kubernetes.io/name: mcp-vw
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
SCAR endpoint: explicit value or the access-vw Service in this namespace.
*/}}
{{- define "mcp-vw.accessURL" -}}
{{ .Values.access.url | default (printf "https://access-vw.%s.svc.cluster.local:9443/services/access" .Release.Namespace) }}
{{- end }}
