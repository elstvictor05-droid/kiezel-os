# build/

Numbered shell scripts run inside the Containerfile (`00-base.sh`, `10-packages.sh`, ...).
They read `/ctx/config.yaml` with `yq`. Arrives in Phase 1.
