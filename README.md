# Vast Quan + XTM idle job

This image runs two owner workloads inside one Vast.ai background job:

- SRBMiner-MULTI 3.6.9 on GPU 0 for Quan/Quantus.
- XMRig 6.26.0 on CPU threads 0-14 for Tari (XTM).

The entrypoint expects three positional arguments:

```text
QTC_WALLET XTM_WALLET WORKER_NAME
```

SRBMiner requests a 2750 MHz fixed core clock and an 810 MHz fixed memory clock.
It handles `SIGTERM`/`SIGINT`, stops both miners, and resets both locks when the
idle job exits. Vast background jobs provide the rental-aware pause/resume
lifecycle; the image does not poll for renters.

Both upstream archives are downloaded during the build and verified against
pinned SHA-256 checksums. Wallets are supplied only at runtime and are not
stored in the image.

The `srb2080` image also uses SRBMiner 3.6.9, replacing the former PeakMiner
profile. It preserves the 2080 Ti requests: 1550 MHz core, +250 MHz core offset,
810 MHz memory, and a 30-second OC delay. The driver may reject memory locking
on Turing; a requested setting does not guarantee a successful hardware lock.
CPU mining, pools, runtime wallet arguments, and shutdown behavior are unchanged.
