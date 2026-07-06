#!/usr/bin/env bash
# Provision Grafana: VictoriaMetrics datasource + 2 dashboards + a playlist.
# Idempotent: datasource/dashboards use fixed uids + overwrite.
set -e
# Grafana credentials come from the env, defaulting to a fresh install's admin/admin.
# Override on a secured instance:  GF_AUTH='admin:yourpassword' bash grafana_setup.sh
G="http://${GF_AUTH:-admin:admin}@localhost:3000"

echo ">>> datasource"
curl -s -X POST "$G/api/datasources" -H 'Content-Type: application/json' -d '{
  "name":"VictoriaMetrics","uid":"victoriametrics","type":"prometheus",
  "access":"proxy","url":"http://localhost:8428","isDefault":true
}' | grep -o '"message":"[^"]*"' || true
# if it already existed, make sure url/default are correct
curl -s -X PUT "$G/api/datasources/uid/victoriametrics" -H 'Content-Type: application/json' -d '{
  "name":"VictoriaMetrics","uid":"victoriametrics","type":"prometheus",
  "access":"proxy","url":"http://localhost:8428","isDefault":true
}' >/dev/null || true

echo ">>> dashboard: PM mass"
curl -s -X POST "$G/api/dashboards/db" -H 'Content-Type: application/json' -d '{
 "overwrite":true,"dashboard":{
  "id":null,"uid":"pm-mass","title":"PM Mass Concentration","tags":["air"],
  "schemaVersion":39,"refresh":"30s","time":{"from":"now-7d","to":"now"},
  "panels":[
   {"id":3,"type":"stat","title":"Air Quality (PM2.5, US EPA)",
    "gridPos":{"h":6,"w":24,"x":0,"y":0},
    "datasource":{"type":"prometheus","uid":"victoriametrics"},
    "options":{"colorMode":"background","graphMode":"none","textMode":"value","justifyMode":"center"},
    "fieldConfig":{"defaults":{
      "thresholds":{"mode":"absolute","steps":[
        {"color":"green","value":null},{"color":"yellow","value":12.1},
        {"color":"orange","value":35.5},{"color":"red","value":55.5},
        {"color":"purple","value":150.5},{"color":"dark-red","value":250.5}]},
      "mappings":[
        {"type":"range","options":{"from":0,"to":12,"result":{"text":"GOOD","index":0}}},
        {"type":"range","options":{"from":12.1,"to":35.4,"result":{"text":"MODERATE","index":1}}},
        {"type":"range","options":{"from":35.5,"to":55.4,"result":{"text":"UNHEALTHY (sensitive groups)","index":2}}},
        {"type":"range","options":{"from":55.5,"to":150.4,"result":{"text":"UNHEALTHY","index":3}}},
        {"type":"range","options":{"from":150.5,"to":250.4,"result":{"text":"VERY UNHEALTHY","index":4}}},
        {"type":"range","options":{"from":250.5,"to":100000,"result":{"text":"HAZARDOUS","index":5}}}]},
      "overrides":[]},
    "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":"victoriametrics"},
      "range":true,"editorMode":"code",
      "expr":"pms5003_pm_ugm3{calibration=\"atm\",size=\"pm2.5\"}"}]},
   {"id":1,"type":"timeseries","title":"PM atmospheric (µg/m³)",
    "gridPos":{"h":10,"w":18,"x":0,"y":6},
    "datasource":{"type":"prometheus","uid":"victoriametrics"},
    "fieldConfig":{"defaults":{"unit":"conmicrogm3"},"overrides":[]},
    "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":"victoriametrics"},
      "range":true,"editorMode":"code",
      "expr":"pms5003_pm_ugm3{calibration=\"atm\"}","legendFormat":"{{size}}"}]},
   {"id":2,"type":"stat","title":"PM2.5 now",
    "gridPos":{"h":10,"w":6,"x":18,"y":6},
    "datasource":{"type":"prometheus","uid":"victoriametrics"},
    "fieldConfig":{"defaults":{"unit":"conmicrogm3","thresholds":{"mode":"absolute",
      "steps":[{"color":"green","value":null},{"color":"yellow","value":12},
               {"color":"orange","value":35},{"color":"red","value":55}]}},"overrides":[]},
    "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":"victoriametrics"},
      "range":true,"editorMode":"code",
      "expr":"pms5003_pm_ugm3{calibration=\"atm\",size=\"pm2.5\"}"}]}
  ]}}' | grep -o '"status":"[^"]*"' || true

echo ">>> dashboard: particle counts"
curl -s -X POST "$G/api/dashboards/db" -H 'Content-Type: application/json' -d '{
 "overwrite":true,"dashboard":{
  "id":null,"uid":"pm-counts","title":"Particle Counts","tags":["air"],
  "schemaVersion":39,"refresh":"30s","time":{"from":"now-7d","to":"now"},
  "panels":[
   {"id":1,"type":"timeseries","title":"Particles per 0.1L (cumulative ≥ size µm)",
    "gridPos":{"h":10,"w":24,"x":0,"y":0},
    "datasource":{"type":"prometheus","uid":"victoriametrics"},
    "targets":[{"refId":"A","datasource":{"type":"prometheus","uid":"victoriametrics"},
      "range":true,"editorMode":"code",
      "expr":"pms5003_particles","legendFormat":"≥{{size_um}}µm"}]}
  ]}}' | grep -o '"status":"[^"]*"' || true

echo ">>> playlist"
BODY='{"name":"Air Quality","interval":"30s","items":[{"type":"dashboard_by_uid","value":"pm-mass","order":1},{"type":"dashboard_by_uid","value":"pm-counts","order":2}]}'
# update-in-place if it already exists so the URL stays stable across reruns
PLUID=$(curl -s "$G/api/playlists" | grep -o '"uid":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$PLUID" ]; then
  curl -s -X PUT "$G/api/playlists/$PLUID" -H 'Content-Type: application/json' -d "$BODY" >/dev/null
  echo "\"uid\":\"$PLUID\" (updated)"
else
  curl -s -X POST "$G/api/playlists" -H 'Content-Type: application/json' -d "$BODY" | grep -o '"uid":"[^"]*"' || true
fi
echo
echo "Done."
