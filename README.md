# Home Assistant Configuration

Personal [Home Assistant](https://home-assistant.io/) configuration.

## Platform

| | |
| --- | --- |
| **Hardware** | Raspberry Pi 5 |
| **Install** | Home Assistant OS |
| **Network** | UniFi (Protect, Network) |
| **Protocols** | Z-Wave (Z-Wave JS UI), Matter/Thread, WiFi (LIFX, Nanoleaf) |

## Repository Structure

```text
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

## Checks on the Pi

The repository's native hooks run on the Pi too, in the Terminal & SSH add-on,
which keeps only `/config` across an update:

- The add-on installs pre-commit, Node, npm and Vale itself, from its own
  `apks` option.
- `tools/install-hooks.sh` keeps the pinned gitleaks binary under
  `/config/.tools/` and runs the native `pre-commit install`. pre-commit keeps
  its environments under `/config/.tools/pre-commit`.
- The operator's private scan inputs, the gitleaks rules and the rosters, are
  kept current under `/config/.tools/operator-config/` by the review host's
  merged-main apply. They are never tracked here and never printed.

Set up once from the add-on, and check after an add-on update:

```sh
bash /config/tools/install-hooks.sh
bash /config/tools/install-hooks.sh --check
```

An SSH command loads no shell profile, so source the hook settings before
committing or pushing on the Pi:

```sh
. /config/tools/pi-hook-env.sh
```

Without them the scans fail closed and refuse the commit. After a merge, bring
the Pi level with the default branch with `tools/pi-sync.sh`.

## History

Originally installed ~2017 on a Supermicro 1U rack server running Ubuntu with Docker. Hand-edited YAML, split across `automation/` and `script/` directories with `!include_dir_merge_list`. Migrated to HAOS on Raspberry Pi 5 in March 2025. Config consolidated to `automations.yaml` and `scripts.yaml` (UI-managed). Repository synced to current state in March 2026.

## Configuration validation

Home Assistant checks its own configuration on the house: `ha core check`, or
the HA MCP configuration check, validates the installed `/config` against the
Core the house runs. A change is checked there before it's recorded here. CI
runs the shared estate checks; the native hooks add YAML syntax and duplicate
keys, the network-rule fixtures, and the script interface tests in `tests/` on
push. None of these replaces Home Assistant's own check.

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
| --- | --- | --- |
| `sonos_api_url` | Complete API URL | Previous `pyscript/sonos_group.py` constant |
| `lifxlan_living_room_tv_ht_on` | Complete `python /config/python/scenes/living_room_tv_ht_on.py MAC ADDRESS` command | Previous script constructor |

The existing `lifx_bedroom_tiles_wakeup` secret is unrelated to
`python/scenes/bedroom_tiles_wakeup.py` and remains unchanged. That Python file
is a manual utility after this migration; supply MAC then address only if an
explicit consumer is identified later.

Take a backup, prepare private values first, check the configuration on the house, then use HA's
supported reload/deployment mechanism during an idle period. Verify the Sonos
grouping service and living-room scene caller after deployment. Retain the backup
for rollback. The live HA-managed checkout must not be overwritten or rebased
to deploy this change. Manual `restart_sonarr.py` now takes a URL argument and
`python/scenes/test.py` takes MAC then address. Arguments can briefly appear in
the container process list; this interface is for device addresses, not tokens
or passwords.

The scanner rejects IPv4 and colon/hyphen-separated MAC literals, except protocol
constants and explicit documentation fixtures. Genuine instance values are
not exempted. Cleaning the current tree does not rewrite previously published
Git history.
