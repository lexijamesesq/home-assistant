"""Read LIFX zone colors in unique chunks."""


@service
async def lifx_read_zones(entity_id="light.living_room_tv", tag="unknown"):
    """Read all zone colors, log in unique tagged chunks."""
    manager = hass.data["lifx"]
    coordinator = manager.entity_id_to_coordinator.get(entity_id)
    device = coordinator.device

    device.get_extended_color_zones()
    task.sleep(1)

    zones = getattr(device, 'color_zones', None)
    if zones:
        z = [list(z) for z in zones[:40]]
        log.warning(f"ZD_{tag}_A:{z[0:10]}")
        log.warning(f"ZD_{tag}_B:{z[10:20]}")
        log.warning(f"ZD_{tag}_C:{z[20:30]}")
        log.warning(f"ZD_{tag}_D:{z[30:40]}")
