"""LIFX Multizone Control Service for pyscript.

Uses HA's existing LIFX coordinator to access the aiolifx device directly.
Path: hass.data["lifx"].entity_id_to_coordinator[entity_id].device
"""


@service
async def lifx_set_zones(entity_id, colors, format="lifx", power_on=True):
    """Set per-zone colors on a LIFX multizone device.

    Args:
        entity_id: Light entity ID (e.g., 'light.living_room_tv')
        colors: List of (hue, sat, brightness, kelvin) tuples.
        format: 'lifx' for 16-bit values (0-65535), 'ha' for degrees/pct
        power_on: Turn on the device if off (default True)
    """
    manager = hass.data["lifx"]
    coordinator = manager.entity_id_to_coordinator.get(entity_id)
    if coordinator is None:
        log.error(f"lifx_set_zones: No LIFX coordinator for {entity_id}")
        return

    device = coordinator.device

    if format == "ha":
        lifx_colors = [
            (int(h / 360 * 65535) % 65536, int(s / 100 * 65535), int(b / 100 * 65535), int(k))
            for h, s, b, k in colors
        ]
    else:
        lifx_colors = [tuple(c) for c in colors]

    padded = lifx_colors + [(0, 0, 0, 3500)] * (82 - len(lifx_colors))

    device.set_extended_color_zones(padded, len(lifx_colors))

    if power_on:
        service.call("light", "turn_on", entity_id=entity_id)

    log.info(f"lifx_set_zones: Set {len(lifx_colors)} zones on {entity_id}")


@service
async def lifx_move_zones(entity_id, colors, speed=3.0, direction="right", format="lifx", power_on=True):
    """Set per-zone colors then start the Move effect."""
    await lifx_set_zones(entity_id=entity_id, colors=colors, format=format, power_on=power_on)

    task.sleep(0.5)

    service.call("lifx", "effect_move",
                 entity_id=entity_id,
                 speed=speed,
                 direction=direction,
                 power_on=power_on)

    log.info(f"lifx_move_zones: Started move on {entity_id} speed={speed} dir={direction}")
