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

The Terminal & SSH App can be rebuilt, while its `/config` mount persists.
The native hook, public scanner bundle, binary and private overlay all live
under that mount. The installer reuses checksum-valid artifacts and reports
incomplete setup until the required configurations are loadable.

From the App's terminal, after preparing the private overlay with
`PI_HOST=ha.example.invalid bash tools/deliver-overlay.sh` on the workstation:

```sh
bash /config/tools/install-hooks.sh
bash /config/tools/install-hooks.sh --check
```

The delivery command uses the existing workstation rules and SSH identity;
substitute the actual SSH host privately. It never prints rule contents.
An optional `init_commands` entry can run `bash /config/tools/install-hooks.sh`
after App startup to detect and repair public runtime drift. Persistence does
not depend on downloading the scanner again on every start.

The hook itself (`tools/pre-push-gitleaks.sh`) scans every outgoing push
with Dotty's fail-closed scanner and the operator's private pattern overlay at
its persistent fixed path (`/config/.tools/operator-config/gitleaks/operator-rules.toml`)
— delivered here from the Mini by `tools/deliver-overlay.sh`, never tracked
in this repo, never echoed anywhere. Neither script edits any Home Assistant
configuration file; the hook runtime, scanner, and overlay are confined to
`.git/hooks/` and the gitignored `.tools/`. A missing or invalid overlay blocks
the push.

## History

Originally installed ~2017 on a Supermicro 1U rack server running Ubuntu with Docker. Hand-edited YAML, split across `automation/` and `script/` directories with `!include_dir_merge_list`. Migrated to HAOS on Raspberry Pi 5 in March 2025. Config consolidated to `automations.yaml` and `scripts.yaml` (UI-managed). Repository synced to current state in March 2026.

## Candidate configuration validation

CI combines the shared estate checks with Home Assistant Core's native
configuration checker. The official Core image is pinned by version and digest
to the installed release. Update that pin when upgrading Core and repeat both
the valid and invalid-automation acceptance probes before relying on the new pin.

CI substitutes `fakesecrets.yaml` for the untracked `secrets.yaml` and mounts the
candidate at `/config`, with network access disabled. `tools/check-ha-config.py`
retains native validation and additionally rejects ERROR logs: Core 2026.6.3 can
disable an invalid automation while returning exit 0, including in strict mode.
The standard pre-commit YAML hook only checks syntax; it does not replace Core.

This checks the proposed public configuration, not the running house. It does
not prove devices, credentials, custom integrations, or automation behavior. The
HA MCP live configuration check validates the installed `/config`; it does not
validate an arbitrary PR checkout. No deployment or reload is triggered by this
workflow.

### Persistent scanner acceptance

After provisioning the public hook bundle and gitleaks binary, run
`bash tools/test-pre-push-gitleaks.sh`. The harness uses synthetic rules and
disposable local repositories; it never reads the real operator overlay or pushes
to GitHub. The operator overlay is mandatory for real Pi pushes. Installation
reports incomplete setup until the overlay is delivered and loadable.

### Private runtime inputs and deployment order

The repository remains public. Home Assistant resolves `!secret` YAML nodes;
standalone Python does not automatically read them. Pyscript uses its native
`pyscript.config["global"]["sonos_api_url"]` setting. The standalone scene and
manual utility scripts take required arguments and have no device-address
fallback. HA already supports a complete `shell_command` value via `!secret`;
that remains the boundary for HA-launched scripts. This uses the estate's
public-code/private-instance-data pattern with HA's supported configuration
mechanism, without a runtime dependency on the estate's 1Password broker.

Before deploying the changed scripts, privately provision these values:

| Secret | Required value | Existing value source |
|---|---|---|
| `sonos_api_url` | Complete API URL | Previous `pyscript/sonos_group.py` constant |
| `lifxlan_living_room_tv_ht_on` | Complete `python /config/python/scenes/living_room_tv_ht_on.py MAC ADDRESS` command | Previous script constructor |
| `lifx_bedroom_tiles_wakeup` | Existing command updated with `MAC ADDRESS` arguments | Previous bedroom script constructor |

Do not copy `fakesecrets.yaml` to production. Take a backup, prepare private
values first, validate the candidate and live configuration, then use HA's
supported reload/deployment mechanism during an idle period. Verify the Sonos
grouping service and both scene callers after deployment. Retain the backup
for rollback. The live HA-managed checkout must not be overwritten or rebased
to deploy this change. Manual `restart_sonarr.py` now takes a URL argument and
`python/scenes/test.py` takes MAC then address. Arguments can briefly appear in
the container process list; this interface is for device addresses, not tokens
or passwords.

The CI image includes exactly Pyscript 2.0.1 with its manifest dependencies so
the added YAML domain is checked, not ignored. Image preparation downloads
public dependencies; candidate execution stays network-disabled. CI does not
exercise live Pyscript services or device behavior.

The scanner rejects IPv4 and colon/hyphen-separated MAC literals, except protocol
constants and explicit documentation fixtures. Genuine instance values are
not exempted. Cleaning the current tree does not rewrite previously published
Git history.

### Retiring the duplicate hosted scan

First merge the paired Dotty declaration, then have the operator run the
provisioner's `--check` and converge steps. The only expected drift is removal
of the duplicate `secret-scan` context; the two shared contexts remain required.
Only after read-back confirms that state should the legacy workflow be removed
and this PR merged. Stop if the provisioner reports unrelated drift.
