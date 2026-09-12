# CI-only derivative of the installed Core release. No house configuration or
# private values are baked into this image. Re-prove positive/negative fixtures
# when updating either the Core pin or the production-matched Pyscript release.
FROM ghcr.io/home-assistant/home-assistant:2026.6.3@sha256:aed891b8f801072302815b4b0fab5adb714182967e9d2e2d4a2be558241c73ad
ADD --checksum=sha256:a3ca4d5a642cb000624fef4095afe7978fb1a09d8392b8712f25fe09103343ad https://github.com/custom-components/pyscript/releases/download/2.0.1/hass-custom-pyscript.zip /tmp/pyscript.zip
# Exact requirements from Pyscript 2.0.1's manifest. Preparation may download
# dependencies; the actual candidate validator always runs without networking.
RUN python -m zipfile -e /tmp/pyscript.zip /opt/ci-pyscript \
    && pip install --no-cache-dir croniter==6.0.0 watchdog==6.0.0 \
    && rm /tmp/pyscript.zip
