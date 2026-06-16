"""Virtual Lexi — behavioral presence simulation.

Intent-driven generation, event-driven execution. The night is generated as a
list of absolute-time occupant-state transitions, persisted to JSON; a single
HA time-trigger automation (virtual_next_event) fires one event at a time via
virtual_lexi_fire_next. There is NO sustained task — HA's time machinery does
all the waiting, so a pyscript reload or HA reboot loses nothing (plan file +
counter cursor + input_datetime persist; the trigger re-arms).

The simulator's vocabulary is INTENTS (watch / den_work / go_to_bed / wake).
Each intent expands into occupant-state NUDGES the existing lighting system
reacts to; the only direct light ops are the ones real Lexi performs (the
"turn off downstairs lights" voice command, the bedroom switch).
"""
import random
import json
import datetime as dt

DTFMT = "%Y-%m-%d %H:%M:%S"
RECIPE = "input_text.virtual_plan_recipe"

ACTIVE = "input_boolean.virtual_lexi"
SLEEP = "input_boolean.virtual_sleep"
VHT = "input_boolean.virtual_home_theater"
VHTP = "input_boolean.virtual_home_theater_playing"
NEXT_DT = "input_datetime.virtual_next_event_time"
CURSOR = "counter.virtual_event_cursor"

GROUP_DOWNSTAIRS = "group.downstairs_inside_lights"
BEDROOM_OFF = ["light.bedroom", "light.bedroom_switch", "light.bathroom", "light.bathroom_wc_dimmer"]
# Re-asserted (after flags cleared) when the sim is interrupted, so a returning
# resident/guest walks into a correctly-lit house (red-team C3).
BASE_SCRIPTS = [
    "script.lighting_kitchen", "script.lighting_living_room",
    "script.lighting_living_room_tv", "script.lighting_rec_room_canvas",
    "script.lighting_den", "script.lighting_den_cabinets",
    "script.lighting_bedroom", "script.lighting_patio",
    "script.lighting_patio_string_lights",
]


# ----------------------------------------------------------------------------
# Generator (pure) — intent sequencer + pause/bail expanders
# ----------------------------------------------------------------------------
def _ev(t, sc, desc):
    return {"t": t.strftime(DTFMT), "sc": sc, "desc": desc}


def _draw_bedtime(start, rng):
    base = dt.datetime.combine(start.date(), dt.time(0, 0))
    if rng.random() < 0.6:
        mins = rng.uniform(20 * 60 + 15, 21 * 60 + 15)   # early 8:15-9:15
    else:
        mins = rng.uniform(22 * 60, 24 * 60)             # late 10:00-midnight
    bt = base + dt.timedelta(minutes=mins)
    if bt <= start + dt.timedelta(minutes=20):           # late start -> short evening
        bt = start + dt.timedelta(minutes=rng.uniform(20, 40))
    return bt


def _draw_wake(start, rng):
    # Fri/Sat night -> weekend (later) morning; else weekday early.
    if start.weekday() in (4, 5):
        mins = rng.uniform(6 * 60 + 30, 8 * 60 + 30)
    else:
        mins = rng.uniform(5 * 60 + 15, 5 * 60 + 40)
    wbase = dt.datetime.combine((start + dt.timedelta(days=1)).date(), dt.time(0, 0))
    return wbase + dt.timedelta(minutes=mins)


def _split(total, k, rng):
    if k <= 1:
        return [total]
    cuts = sorted([rng.uniform(0, 1) for _ in range(k - 1)])
    pts = [0.0] + cuts + [1.0]
    return [max(1.0, (pts[i + 1] - pts[i]) * total) for i in range(k)]


def _expand_watch(events, cursor, bedtime, rng):
    deadline = bedtime - dt.timedelta(minutes=15)
    is_movie = rng.random() < 0.5
    label = "movie" if is_movie else "show"
    total = rng.uniform(90, 150) if is_movie else rng.uniform(20, 45)
    if rng.random() < 0.35:                       # bail: abandons partway -> den
        total *= rng.uniform(0.3, 0.7)
        end_desc = "Bored — head up to the den"
    else:
        end_desc = label.capitalize() + " ended — TV off"
    events.append(_ev(cursor, "tv_browsing", "Turn on TV, browse for a " + label))
    cursor += dt.timedelta(minutes=rng.uniform(2, 10))
    if cursor >= deadline:
        cursor = deadline
        events.append(_ev(cursor, "tv_off", "Nothing on — TV off"))
        return cursor
    npause = rng.randint(0, 3) if is_movie else rng.randint(0, 2)   # pauses: return
    for i, ch in enumerate(_split(total, npause + 1, rng)):
        events.append(_ev(cursor, "tv_playing", "Watching the " + label if i == 0 else "Resume"))
        cursor += dt.timedelta(minutes=ch)
        if cursor >= deadline:
            cursor = deadline
            break
        events.append(_ev(cursor, "tv_browsing", "Pause — phone / kitchen"))
        cursor += dt.timedelta(minutes=rng.uniform(1, 5))
        if cursor >= deadline:
            cursor = deadline
            break
    events.append(_ev(cursor, "tv_off", end_desc))
    return cursor


def _expand_den(events, cursor, bedtime, rng):
    # Den/computer: she's upstairs, TV already off, den lit all evening -> no
    # externally-visible change. Pure time advance (the oscillation gap).
    cursor += dt.timedelta(minutes=rng.uniform(20, 90))
    cap = bedtime - dt.timedelta(minutes=15)
    return cursor if cursor < cap else cap


def _expand_bed(events, bedtime, rng):
    events.append(_ev(bedtime, "goodnight_downstairs", "Head to bed — turn off downstairs lights"))
    t = bedtime + dt.timedelta(minutes=rng.uniform(2.5, 3.5))        # walk upstairs (~3 min)
    events.append(_ev(t, "sleep_mode", "Reach bedroom — sleep mode (bedroom warms, bathroom on)"))
    early = (bedtime.hour * 60 + bedtime.minute) < (21 * 60 + 15)
    lag = rng.uniform(45, 90) if early else rng.uniform(15, 30)      # inverse to bedtime
    t2 = t + dt.timedelta(minutes=lag)
    events.append(_ev(t2, "lights_out", "Crawl into bed — lights out"))
    return t2


def _normalize(events):
    """Enforce >=45s spacing by nudging later events forward (the deadline
    clamps in _expand_watch can otherwise produce sub-minute gaps). The 15-min
    pre-bedtime margin absorbs the seconds of drift."""
    out = []
    prev = None
    for e in events:
        t = dt.datetime.strptime(e["t"], DTFMT)
        if prev is not None and (t - prev).total_seconds() < 45:
            t = prev + dt.timedelta(seconds=45)
            e = {"t": t.strftime(DTFMT), "sc": e["sc"], "desc": e["desc"]}
        out.append(e)
        prev = t
    return out


def generate_plan(start, rng):
    events = []
    bedtime = _draw_bedtime(start, rng)
    cursor = start + dt.timedelta(minutes=rng.uniform(3, 12))        # settle in
    activity = "watch" if rng.random() < 0.7 else "den"
    guard = 0
    while cursor < bedtime - dt.timedelta(minutes=20) and guard < 12:
        if activity == "watch":
            cursor = _expand_watch(events, cursor, bedtime, rng)
            activity = "den"
        else:
            cursor = _expand_den(events, cursor, bedtime, rng)
            activity = "watch"
        guard += 1
    _expand_bed(events, bedtime, rng)
    events.append(_ev(_draw_wake(start, rng), "wake", "Wake up"))
    return _normalize(events)


def _valid(events):
    scs = [e["sc"] for e in events]
    if not all([x in scs for x in ("goodnight_downstairs", "lights_out", "wake")]):
        return False
    times = [dt.datetime.strptime(e["t"], DTFMT) for e in events]
    for i in range(1, len(times)):
        if (times[i] - times[i - 1]).total_seconds() < 30:
            return False
    return True


def _remap(events, start, time_scale):
    """Compress absolute times (anchored at start) for accelerated testing.
    Anchored at start (not now) so regeneration from the recipe reproduces it."""
    if time_scale == 1.0:
        return events
    out = []
    for e in events:
        orig = dt.datetime.strptime(e["t"], DTFMT)
        new = start + dt.timedelta(seconds=(orig - start).total_seconds() / time_scale)
        out.append({"t": new.strftime(DTFMT), "sc": e["sc"], "desc": e["desc"]})
    return out


# ----------------------------------------------------------------------------
# Persistence — a tiny reproducible recipe (seed + start + scale), NOT the plan.
# pyscript has no file I/O; regenerating from the recipe is deterministic and
# survives reboot via the durable input_text + counter + input_datetime.
# ----------------------------------------------------------------------------
def _current_events():
    r = json.loads(state.get(RECIPE))
    start = dt.datetime.strptime(r["start"], DTFMT)
    events = _remap(generate_plan(start, random.Random(r["seed"])), start, r["scale"])
    return events, r["shadow"]


# ----------------------------------------------------------------------------
# Occupant-state vocabulary (nudges the existing lighting system reacts to;
# goodnight + lights_out are Lexi's own direct controls)
# ----------------------------------------------------------------------------
def _apply(sc):
    if sc == "tv_browsing":
        input_boolean.turn_on(entity_id=VHT)
        input_boolean.turn_off(entity_id=VHTP)
    elif sc == "tv_playing":
        input_boolean.turn_on(entity_id=VHT)
        input_boolean.turn_on(entity_id=VHTP)
    elif sc == "tv_off":
        input_boolean.turn_off(entity_id=VHT)
        input_boolean.turn_off(entity_id=VHTP)
    elif sc == "goodnight_downstairs":
        light.turn_off(entity_id=GROUP_DOWNSTAIRS)
    elif sc == "sleep_mode":
        # Set virtual_sleep — the EXISTING core sleep automations react (same as for
        # real mode_sleep, now augmented to also fire on virtual_sleep): 'Bedroom
        # Lights at Night - Sleep Mode On' warms the bedroom instantly; 'Sleep Mode
        # Started - Turn Off Lights' clears den/den_cabinets/patio after 2 min. Only
        # the bathroom needs explicit handling — Zooz-remote, no sleep automation covers it (P5).
        input_boolean.turn_on(entity_id=SLEEP)
        light.turn_on(entity_id="light.bathroom")
    elif sc == "lights_out":
        for ent in BEDROOM_OFF:
            light.turn_off(entity_id=ent)
    elif sc == "wake":
        input_boolean.turn_off(entity_id=SLEEP)
    else:
        log.warning("virtual_lexi: unknown state_change %s", sc)


def _arm(tstr):
    target = dt.datetime.strptime(tstr, DTFMT)
    floor = dt.datetime.now() + dt.timedelta(seconds=2)
    if target < floor:
        target = floor
    input_datetime.set_datetime(entity_id=NEXT_DT, datetime=target.strftime(DTFMT))


def _fire_one():
    """Execute the event at the cursor, advance, schedule the next. Returns
    True if another event remains armed."""
    if state.get(ACTIVE) != "on":
        return False
    events, shadow = _current_events()
    idx = int(float(state.get(CURSOR)))
    if idx >= len(events):
        input_boolean.turn_off(entity_id=ACTIVE)
        return False
    e = events[idx]
    log.info("virtual_lexi: [%s] %s", e["sc"], e["desc"])
    if not shadow:
        _apply(e["sc"])
    counter.increment(entity_id=CURSOR)
    if idx + 1 < len(events):
        _arm(events[idx + 1]["t"])
        return True
    input_boolean.turn_off(entity_id=ACTIVE)   # past the terminal 'wake' event
    return False


# ----------------------------------------------------------------------------
# Services
# ----------------------------------------------------------------------------
@service
def virtual_lexi_start(time_scale=1.0, shadow=False):
    """Generate tonight's plan as a reproducible recipe and arm event 0."""
    input_boolean.turn_off(entity_id=SLEEP)            # defensive (stale flag)
    start = dt.datetime.now()
    scale = float(time_scale)
    seed = random.randint(1, 2000000000)
    base = None
    for _ in range(10):
        cand = generate_plan(start, random.Random(seed))
        if _valid(cand):
            base = cand
            break
        seed = random.randint(1, 2000000000)
    if base is None:
        log.warning("virtual_lexi: failed to generate a valid plan")
        return
    events = _remap(base, start, scale)
    input_text.set_value(entity_id=RECIPE, value=json.dumps(
        {"seed": seed, "start": start.strftime(DTFMT), "scale": scale, "shadow": bool(shadow)}))
    counter.reset(entity_id=CURSOR)
    input_boolean.turn_on(entity_id=ACTIVE)
    _arm(events[0]["t"])
    log.info("virtual_lexi: plan (%d events, scale=%s, shadow=%s):\n%s",
             len(events), time_scale, shadow,
             "\n".join(["  %s  %-22s %s" % (e["t"][11:16], e["sc"], e["desc"]) for e in events]))


@service
def virtual_lexi_fire_next():
    """Engine tick — invoked by automation.virtual_next_event."""
    _fire_one()


@service
def virtual_lexi_catchup():
    """Resilience — on HA start, fire any events whose time passed during the
    outage so the schedule resyncs (red-team C1)."""
    if state.get(ACTIVE) != "on":
        return
    guard = 0
    while state.get(ACTIVE) == "on" and guard < 60:
        try:
            target = dt.datetime.strptime(state.get(NEXT_DT), DTFMT)
        except (ValueError, TypeError):
            break
        if target > dt.datetime.now():
            break
        if not _fire_one():
            break
        guard += 1


@service
def virtual_lexi_stop():
    """Escape hatch — clear all virtual flags, neutralize the pending fire, and
    re-assert the full base lighting layer (red-team C3)."""
    input_boolean.turn_off(entity_id=ACTIVE)
    input_boolean.turn_off(entity_id=SLEEP)
    input_boolean.turn_off(entity_id=VHT)
    input_boolean.turn_off(entity_id=VHTP)
    past = (dt.datetime.now() - dt.timedelta(hours=1)).strftime(DTFMT)
    input_datetime.set_datetime(entity_id=NEXT_DT, datetime=past)
    task.sleep(0.3)                                    # let flags settle before relight
    for scr in BASE_SCRIPTS:
        script.turn_on(entity_id=scr)
    log.info("virtual_lexi: stopped — flags cleared, base lighting re-asserted")


@service
def virtual_lexi_test_action(action="tv_browsing"):
    """Integration testing — apply a single state_change."""
    log.info("virtual_lexi test: %s", action)
    _apply(action)
