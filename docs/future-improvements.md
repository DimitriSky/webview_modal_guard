# Future improvements · WV-MODAL-GUARD

Items from the scoped 2026-10-08 package audit. None is a confirmed outstanding
important defect in the scenarios verified by that audit.

1. **Verification extension:** repeat the full physical input matrix on the
   audited revision, including URL hover, right/middle buttons, trackpad
   magnify/rotate/swipe, momentum scroll, native window controls and a second
   window. Keep physical evidence separate from self-posted routing checks.
   Existing physical Settings evidence is historical; the latest lifecycle
   qualification does not replace it. Repeat relevant checks on supported
   macOS/Flutter versions when those versions change.
2. **P3, optional API completeness:** expose additional Material dialog options
   (`anchorPoint`, `requestFocus`, `traversalEdgeBehavior`, `animationStyle`)
   if a consuming application needs them. The current helper supports the
   Settings/URL modal contract being reviewed.
3. **P3, optional event API cleanup:** restrict `buttonNumber` queries to button
   up/drag/down events by checking the type first. Real tracking and scroll
   events did not crash in this audit, so this is not treated as a reproduced
   crash fix. Keep coverage of non-button events if this is changed later.

Partial popovers and every native menu/window tracking loop require a separate
policy and scope; they are not silently included in the full-window modal
guarantee. Clearing pre-existing CSS hover remains a documented limitation,
not a DOM mutation to add as part of this audit.
