# Home Assistant Configuration

Personal [Home Assistant](https://home-assistant.io/) configuration, version-controlled with automatic commits via [HomeAssistantVersionControl](https://github.com/saihgupr/HomeAssistantVersionControl).

## Platform

| | |
|---|---|
| **Hardware** | Raspberry Pi 5 |
| **Install** | Home Assistant OS |
| **Network** | UniFi (Protect, Network) |
| **Protocols** | Z-Wave (Z-Wave JS UI), Matter/Thread, WiFi (LIFX, Nanoleaf) |

## Repository Structure

```
configuration.yaml          # Main config — includes, integrations, utility meters
automations.yaml            # All automations (UI-managed)
scripts.yaml                # All scripts (UI-managed)

blueprints/                 # Automation and template blueprints
template/                   # Template sensors — climate, weather, calendar, status
themes/                     # Catppuccin, Bubble, custom themes

lovelace/dashboard/         # Tablet dashboard (YAML mode)
  button_card_templates/    # Custom button card templates
  partials/                 # Dashboard view partials
  popups/                   # Camera and home popups
ui-dashboard.yaml           # Tablet dashboard root

sensor.yaml                 # Platform sensors (InfluxDB, REST, etc.)
customize.yaml              # Entity customizations
group.yaml                  # Groups
input_boolean.yaml          # Input helpers
input_number.yaml
input_select.yaml
input_text.yaml
rest_command.yaml            # REST commands
shell_command.yaml           # Shell commands
scene.yaml                  # Scenes
binary_sensor.yaml
media_player.yaml
```

## What's Tracked

- All YAML configuration files
- Selective `.storage/` — lovelace dashboards, input helpers, zones, persons
- Themes and blueprints

## What's Not Tracked

- `secrets.yaml` — credentials and API keys
- `.storage/` registries — entity, device, config entries (regenerated on startup)
- `custom_components/` — managed by HACS
- `www/` — frontend cards managed by HACS
- Databases, logs, backups, binaries

## History

Originally installed ~2017 on a Supermicro 1U rack server running Ubuntu with Docker. Hand-edited YAML, split across `automation/` and `script/` directories with `!include_dir_merge_list`. Migrated to HAOS on Raspberry Pi 5 in March 2025. Config consolidated to `automations.yaml` and `scripts.yaml` (UI-managed). Repository synced to current state in March 2026.

