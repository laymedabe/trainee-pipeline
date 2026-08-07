# Design Decisions

## RAM Allocation Deviation
**Deviation:** Allocated 1GB of RAM per VM instead of the requested 2GB.
**Reasoning:** The host physical laptop only had 3GB of available RAM. Provisioning 4GB total would exceed host capacity, trigger the OOM killer, and cause system instability.
