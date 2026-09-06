# Home Assistant Configuration

Personal [Home Assistant](https://home-assistant.io/) configuration.

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

## Pre-push secret scan (on the Pi)

This repo's working copy lives in the Terminal & SSH add-on's container,
which is rebuilt on every add-on update — a manually-installed git hook or a
manually-placed binary does not survive that. `tools/install-hooks.sh` is
the thing that re-applies both, idempotently, so it can run every time the
container starts rather than being a one-off step someone has to remember.

**One-time (or after a rebuild), from the add-on's own terminal:**

```
cd /config
bash tools/install-hooks.sh          # installs .tools/gitleaks + the pre-push hook
bash tools/install-hooks.sh --check  # read-only: reports drift, changes nothing
```

**To survive a container rebuild automatically**, add to the Terminal & SSH
add-on's configuration (Settings → Add-ons → Terminal & SSH → Configuration),
under `init_commands`:

```yaml
init_commands:
  - "bash /config/tools/install-hooks.sh"
```

This re-applies the hook and the gitleaks binary on every add-on start —
the mechanism the estate previously tried and lost to a rebuild once
already (recorded in `System/Knowledge/leak-prevention-architecture.md`),
this time with a script that re-runs instead of a step that gets forgotten.

The hook itself (`tools/pre-push-gitleaks.sh`) scans every outgoing push
with gitleaks' default rules, plus the operator's private pattern overlay if
present at its fixed path on this device (`~/.config/gitleaks/operator-rules.toml`)
— delivered here from the Mini by `tools/deliver-overlay.sh`, never tracked
in this repo, never echoed anywhere. Neither script edits any Home Assistant
configuration file; both are confined to `.git/hooks/` and `.tools/`.

## History

Originally installed ~2017 on a Supermicro 1U rack server running Ubuntu with Docker. Hand-edited YAML, split across `automation/` and `script/` directories with `!include_dir_merge_list`. Migrated to HAOS on Raspberry Pi 5 in March 2025. Config consolidated to `automations.yaml` and `scripts.yaml` (UI-managed). Repository synced to current state in March 2026.

