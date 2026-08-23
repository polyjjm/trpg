# Node draft/live split rollout

## New storage model

- `storyPacks/{packId}/draftNodes/{nodeId}`: author/admin editor state, pendingAction,
  rejectionReason, approvalRequestedAt, latest approved `liveSnapshot` baseline.
- `storyPacks/{packId}/nodes/{nodeId}`: reader/TTS compatibility document. Author
  autosave never writes here. Admin approval is the only content path that updates
  `liveSnapshot`.

This removes the old structural leak where editing an already-published node replaced
reader-visible document fields while `status == published` stayed true.

## Required deployment order

1. Deploy Functions with `backfillNodeDraftDocuments`.
2. Run `backfillNodeDraftDocuments` once as admin. It is idempotent and never overwrites
   an existing draft document.
3. Deploy Firestore Rules for `draftNodes`.
4. Deploy the admin client using `draftNodes`.
5. After the migration is verified, remove legacy editor write permissions from `nodes`.

## Required Firestore Rules

`draftNodes` must be readable/writable only by the pack author or admin. Readers must have
no access. The existing `nodes` author write rule must then be narrowed so normal author
clients cannot save draft content into reader-facing live documents anymore; approval
writes may be moved to an admin Cloud Function in a later hardening pass if client-side
admin approval becomes difficult to express safely in Rules.

The admin pending queue's collectionGroup changes from `nodes` to `draftNodes`, so the
recursive collectionGroup rule must also permit author/admin review access for
`draftNodes` and no reader access.

## TTS preview compatibility

Existing `previewNodeTts` checks for `storyPacks/{packId}/nodes/{nodeId}` before creating a
preview cache. For an already-published edit this live document exists, so preview keeps
working. For a brand-new never-published draft there is intentionally no live document;
that case needs a follow-up preview implementation that stores temporary cache by draft
path (or skips Firestore cache and returns a short-lived result directly). Until that is
added, this PR should remain Draft and must not be deployed alone.

## Rollback

The migration only copies documents and keeps legacy `nodes` intact. Rolling the admin
client back therefore restores the old editor path without data loss. `draftNodes` can be
left in place while diagnosing a rollback.
