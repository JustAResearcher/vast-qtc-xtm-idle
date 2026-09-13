# Vast Pearl + XTM idle job

This image runs two owner workloads inside one Vast.ai background job:

- SRBMiner-MULTI 3.6.6 on GPU 0 for PearlHash (Pearl + Nock payout login).
- XMRig 6.26.0 on CPU threads 0-14 for Tari (XTM).

The entrypoint expects three positional arguments:

```text
PEARL_NOCK_LOGIN XTM_WALLET WORKER_NAME
```

It handles `SIGTERM`/`SIGINT`, stops both miners, and resets NVIDIA core and
memory locks before the container exits. Vast background jobs provide the
rental-aware pause/resume lifecycle; the image does not poll for renters.

Both upstream archives are downloaded during the build and verified against
pinned SHA-256 checksums. Wallets are supplied only at runtime and are not
stored in the image.
