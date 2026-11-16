{{/* Shared arkime image */}}
{{- define "malcolm.arkime.image" -}}
{{- $root := .root -}}
{{- $root.Values.image.arkime_container_override | default (printf "%s/arkime:%s" $root.Values.image.repository $root.Chart.AppVersion) -}}
{{- end -}}

{{/* Shared arkime livenessProbe */}}
{{- define "malcolm.arkime.livenessProbe" -}}
livenessProbe:
  exec:
    command:
      - /usr/local/bin/container_health.sh
  initialDelaySeconds: 210
  periodSeconds: 90
  timeoutSeconds: 15
  successThreshold: 1
  failureThreshold: 10
{{- end -}}

{{/*
Arkime env entries contributed by the chart's optional features and values:
  - maxmind.enabled: point geoLite2ASN/geoLite2Country at the shared GeoIP volume
    (Arkime >= 5.6 reads ARKIME__<setting> env vars as [default] section overrides)
    and blank the MaxMind credentials so each Arkime pod skips its own startup
    download (maxmind-mmdb-download.sh just exits non-fatally).
  - arkime_env.extraEnv (all Arkime containers), then <workload>.extraEnv.
User-supplied entries come last so they win over anything the chart sets.

Params:
  root: $
  workload: string   # values key for the workload: arkime_offline or arkime_live
*/}}
{{- define "malcolm.arkime.extraEnv" -}}
{{- $root := .root -}}
{{- $wl := index $root.Values .workload | default (dict) -}}
{{- $env := list -}}
{{- if $root.Values.maxmind.enabled -}}
{{- $mmdb := trimSuffix "/" $root.Values.maxmind.arkime_mount_path -}}
{{- $env = concat $env (list
      (dict "name" "ARKIME__geoLite2ASN" "value" (printf "%s/GeoLite2-ASN.mmdb" $mmdb))
      (dict "name" "ARKIME__geoLite2Country" "value" (printf "%s/GeoLite2-Country.mmdb" $mmdb))
      (dict "name" "MAXMIND_GEOIP_DB_ACCOUNT_ID" "value" "")
      (dict "name" "MAXMIND_GEOIP_DB_LICENSE_KEY" "value" "")
      (dict "name" "MAXMIND_GEOIP_DB_ALTERNATE_DOWNLOAD_URL" "value" "")
    ) -}}
{{- end -}}
{{- $env = concat $env ($root.Values.arkime_env.extraEnv | default (list)) ($wl.extraEnv | default (list)) -}}
{{- toYaml $env -}}
{{- end -}}

{{/*
Arkime volumeMounts contributed by maxmind.enabled, arkime_env.extraVolumeMounts
and <workload>.extraVolumeMounts. Same params as malcolm.arkime.extraEnv.
*/}}
{{- define "malcolm.arkime.extraVolumeMounts" -}}
{{- $root := .root -}}
{{- $wl := index $root.Values .workload | default (dict) -}}
{{- $mounts := list -}}
{{- if $root.Values.maxmind.enabled -}}
{{- $mounts = append $mounts (dict "name" "maxmind-volume" "mountPath" $root.Values.maxmind.arkime_mount_path "readOnly" true) -}}
{{- end -}}
{{- $mounts = concat $mounts ($root.Values.arkime_env.extraVolumeMounts | default (list)) ($wl.extraVolumeMounts | default (list)) -}}
{{- toYaml $mounts -}}
{{- end -}}

{{/*
Arkime pod volumes contributed by maxmind.enabled, arkime_env.extraVolumes and
<workload>.extraVolumes. Emits list items (or nothing) for appending under
`volumes:`. Same params as malcolm.arkime.extraEnv.
*/}}
{{- define "malcolm.arkime.extraVolumes" -}}
{{- $root := .root -}}
{{- $wl := index $root.Values .workload | default (dict) -}}
{{- $vols := list -}}
{{- if $root.Values.maxmind.enabled -}}
{{- $vols = append $vols (dict "name" "maxmind-volume" "persistentVolumeClaim" (dict "claimName" ($root.Values.maxmind.storage.existingClaim | default "maxmind-claim") "readOnly" true)) -}}
{{- end -}}
{{- $vols = concat $vols ($root.Values.arkime_env.extraVolumes | default (list)) ($wl.extraVolumes | default (list)) -}}
{{- if $vols -}}
{{ toYaml $vols }}
{{- end -}}
{{- end -}}

{{/*
Generic arkime container (emits a list item).

Params:
  root: $
  name: string
  workload: string (required)       # values key: arkime_offline or arkime_live; selects
                                    #   <workload>.extraEnv / extraVolumeMounts
  ports: list (optional)            # list of {name, protocol, containerPort}
  envFrom: list (required)          # full envFrom list (toYaml-able)
  env: list (optional)              # chart-defined env entries; maxmind and
                                    #   extraEnv entries are appended after these
  securityContext: map (optional)   # securityContext map
  volumeMounts: list (required)     # full mount list; maxmind and extraVolumeMounts
                                    #   entries are appended after these
*/}}
{{- define "malcolm.arkime.container" -}}
{{- $root := .root -}}
{{- $name := .name | default "arkime-container" -}}
{{- $ports := .ports | default (list) -}}
{{- $envFrom := .envFrom | default (list) -}}
{{- $extraArgs := dict "root" $root "workload" .workload -}}
{{- $env := concat (.env | default (list)) (include "malcolm.arkime.extraEnv" $extraArgs | fromYamlArray) -}}
{{- $sc := .securityContext | default (dict) -}}
{{- $mergedSc := merge (dict "runAsGroup" 0 "runAsUser" 0) $sc -}}
{{- $mounts := concat (.volumeMounts | default (list)) (include "malcolm.arkime.extraVolumeMounts" $extraArgs | fromYamlArray) -}}

- name: {{ $name }}
  image: "{{ include "malcolm.arkime.image" (dict "root" $root) }}"
  imagePullPolicy: "{{ $root.Values.image.pullPolicy }}"
  stdin: false
  tty: true
  securityContext:
{{ toYaml $mergedSc | nindent 4 }}
{{- if gt (len $ports) 0 }}
  ports:
{{ toYaml $ports | nindent 4 }}
{{- end }}
  envFrom:
{{ toYaml $envFrom | nindent 4 }}
{{- if gt (len $env) 0 }}
  env:{{ toYaml $env | nindent 4 }}
{{- end }}
{{ include "malcolm.arkime.livenessProbe" . | nindent 2 }}
  volumeMounts:
{{ toYaml $mounts | nindent 4 }}
{{- end -}}
