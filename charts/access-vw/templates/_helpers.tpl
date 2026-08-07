{{/*
Image reference: registry/repository:tag (tag defaults to appVersion).
*/}}
{{- define "access-vw.image" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{- define "access-vw.labels" -}}
app: access-vw
app.kubernetes.io/name: access-vw
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
