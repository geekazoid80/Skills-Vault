# PRTG operations: maps, notifications, API, and pitfalls

Visualisation, alerting, and automation for a running PRTG deployment, plus the common operational traps.

## Maps and dashboards

### Maps

- Visual network diagrams with live sensor-status overlays.
- Drag-and-drop editor with device icons, connections, and labels.
- Background images (floor plans, geographic maps, network diagrams).
- Live data overlay: traffic gauges, status indicators, graphs.
- **Public URL**: publish a map as a web page for NOC displays without login.
- **Rotation**: cycle through multiple maps automatically.

Maps with hundreds of live sensor overlays render slowly. Break a large network into several focused maps.

### Dashboards

- Configurable overview screens with widgets: sensor list, graph, map, top-10 lists, alarms, gauges.
- **Geo Maps**: plot devices on a world map by location.
- Per-user customisation; embeddable in external web pages.

### Reports

- Scheduled reports as PDF or HTML, emailed on a schedule.
- Report types: availability (SLA), uptime, sensor data, top-10.
- Custom time ranges (daily, weekly, monthly, custom).
- Availability reports document SLA compliance.

## Notifications and escalation

### Triggers

| Trigger | Description |
|---|---|
| State change | Device/sensor changes state (up/down/warning) |
| Threshold | Metric exceeds a configured value |
| Speed change | Metric changes rapidly |
| Volume | Cumulative volume exceeds a threshold |
| Unusual | Deviation from a learned baseline |

### Methods

Email, push notification (PRTG mobile app), SMS (HTTP-to-SMS gateway), Slack and Microsoft Teams (incoming webhook), PagerDuty (API), execute program, HTTP action (custom webhook), SNMP trap (to another NMS), syslog, Amazon SNS, and ticket-system integration.

### Escalation chains

```
Level 1: sensor down for 5 minutes      -> email to NOC team
Level 2: not acknowledged in 15 minutes -> SMS to on-call engineer
Level 3: not acknowledged in 30 minutes -> page network manager
Level 4: not acknowledged in 60 minutes -> email to IT director
```

### Maintenance windows

- Scheduled per device, group, or sensor.
- One-time or recurring (daily, weekly, monthly).
- Either pause the sensor (no alerts, no data) or continue monitoring while suppressing notifications.

## HTTP API

PRTG exposes an HTTP-based API for automation.

```
# Get sensor details
GET /api/table.json?content=sensors&output=json&columns=objid,device,sensor,status,lastvalue&apitoken=TOKEN

# Pause a sensor
GET /api/pause.htm?id=2001&pausemsg=Maintenance&action=0&apitoken=TOKEN

# Resume a sensor
GET /api/pause.htm?id=2001&action=1&apitoken=TOKEN

# Get historic sensor data
GET /api/historicdata.json?id=2001&avg=3600&sdate=2026-04-01&edate=2026-04-08&apitoken=TOKEN

# Clone a sensor from a template
GET /api/duplicateobject.htm?id=2001&name=NewSensor&host=DeviceID&apitoken=TOKEN

# Set an object property
GET /api/setobjectproperty.htm?id=2001&name=interval&value=300&apitoken=TOKEN
```

### Authentication

- **API token** (recommended): generate under Setup > Account > API Keys.
- **Passhash**: a user-specific hash for legacy compatibility.
- **Username + password**: basic auth, not recommended for production.

Keep the token in the secret store (`secrets-hygiene`), never inline in a saved URL or a runbook.

### Use cases

- Bulk sensor deployment (a script creates sensors from an inventory).
- Maintenance-window automation (pause/resume from a CI/CD pipeline).
- Custom dashboards pulling PRTG data into Grafana or a web app.
- ITSM integration (auto-create tickets from sensor alerts).

## Common pitfalls

1. **Sensor-count explosion**: auto-discovery creates a sensor for every interface, disk, and service. Review and disable the unneeded ones immediately.
2. **WMI performance**: WMI polling is heavy on both ends; prefer SNMP and use WMI only for Windows-specific metrics.
3. **Remote-probe connectivity**: remote probes need outbound TLS on port 23560; a blocked port causes disconnection and data gaps.
4. **Polling interval too aggressive**: use 5-minute intervals for capacity, 60 seconds only for critical availability.
5. **Not using device templates**: without templates, discovery creates inconsistent sensor sets.
6. **Map performance**: many live overlays render slowly; split into focused maps.
7. **Flow sensor licensing**: flow sensors count toward the limit and may need a higher tier; verify before deploying.
8. **Single core server**: no native HA; plan VM-level HA or use Hosted Monitor.
