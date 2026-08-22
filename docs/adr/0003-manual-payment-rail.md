# ADR 0003: Replace Paymob Rail with Admin-Verified Manual Payments

- **Status**: accepted
- **Date**: 2026-08-22

## Context

ADR 0002 (2026-08-19) ratified "Paymob is the only payment rail" while feature 008 was still unimplemented. Owner review on 2026-08-22 established that no Paymob merchant account was ever created (KYC/commercial registration never completed), so the shipped integration — checkout, webhook, reconcile functions, adapter, secrets — has processed zero real transactions and cannot process any without an onboarding that a parish is unlikely to complete. Separately, every booking already requires a mandatory human step (`AWAITING_CALL` admin phone confirmation), and benchmark research (`specs/011-manual-payment-verification/research.md`) shows mainstream church software treats manual settlement (Breeze "Pay Later", Planning Center cash/check batches) as first-class practice, with none serving Egyptian wallets.

Owner decision this day: replace the electronic gateway rail entirely with manual proof verification ("against everything now").

## Decision

1. **Single manual payment rail**: members pay by Vodafone Cash / InstaPay transfer or cash in person; wallets require submitting a transfer reference plus confirmation screenshot, matched by an administrator against the church's own wallet/statement records (the screenshot is supporting evidence, never the source of truth).
2. **Existing money guarantees unchanged**: booking lifecycle `PENDING_PAYMENT → AWAITING_CALL → CONFIRMED → COMPLETED`, seat-lock expiry cron, waiting-list promotion, and the single sanctioned payments write seam are preserved; new proof actions enter through that seam.
3. **Full deletion of the Paymob stack** (functions, adapter, tests, webhook RPC path, reconcile cron, `PAYMOB_*` env vars, mobile checkout-session flow). Git history preserves reversibility.
4. **Feature 008 alignment**: Event Booking with Extra Services builds its money paths on this rail only — no dual-rail support; admin cash collection becomes part of the same verification surface.

## Consequences

- Constitution amended to v1.2.0: "Paymob is the only payment rail" Product Truth retired in favor of manual verification rail.
- ~1,500 lines of integration code, one nightly cron, six environment secrets, and an entire failure class (webhook/HMAC/reconciliation drift) are removed rather than maintained.
- Refunds become manual (cash/wallet return); acceptable at parish volumes, documented for admins.
- Reintroducing an electronic gateway later would ride the unchanged seam behind new RPCs, requiring only merchant onboarding — not redesign.
