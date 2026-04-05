"""Sonos Grouping Service for pyscript.

Uses node-sonos-http-api (10.0.1.20:5005) for reliable speaker grouping.
The HTTP API handles transport state management internally, avoiding the
UPnP Error 800 and timeout issues with HA's media_player.join and SoCo.
"""

import requests
from urllib.parse import quote

SONOS_API = "http://10.0.1.20:5005"

# Main group excludes Rec Room TV (Beam, TV-connected)
MAIN_GROUP_MEMBERS = ["Bathroom", "Kitchen", "Living Room", "Rec Room", "Den", "Move"]
DEFAULT_COORDINATOR = "Bedroom"


def _api_call(path):
    """Call node-sonos-http-api and return success status."""
    url = f"{SONOS_API}/{quote(path)}"
    try:
        resp = task.executor(requests.get, url, timeout=10)
        data = resp.json()
        return data.get("status") == "success"
    except Exception as e:
        log.warning(f"sonos_group: API call failed: {path}: {e}")
        return False


@service
def sonos_group_all(coordinator_name=None, delay=2):
    """Group all main Sonos speakers to a coordinator.

    Uses node-sonos-http-api to leave/join speakers sequentially.

    Args:
        coordinator_name: Coordinator speaker name (default: Bedroom)
        delay: Seconds between join operations (default: 2)
    """
    if coordinator_name is None:
        coordinator_name = DEFAULT_COORDINATOR

    log.info(f"sonos_group_all: Grouping {len(MAIN_GROUP_MEMBERS)} speakers "
             f"to {coordinator_name}")

    # Phase 1: Leave coordinator first so it's standalone for joins
    _api_call(f"{coordinator_name}/leave")
    task.sleep(1)

    # Phase 2: Leave all members
    for name in MAIN_GROUP_MEMBERS:
        _api_call(f"{name}/leave")

    task.sleep(delay)

    # Phase 3: Join each member to coordinator
    joined = []
    failed = []
    for name in MAIN_GROUP_MEMBERS:
        ok = _api_call(f"{name}/join/{coordinator_name}")
        if ok:
            joined.append(name)
        else:
            failed.append(name)
        task.sleep(delay)

    log.info(f"sonos_group_all: {len(joined)}/{len(MAIN_GROUP_MEMBERS)} "
             f"joined to {coordinator_name}. "
             f"{'Failed: ' + str(failed) if failed else 'All succeeded.'}")
