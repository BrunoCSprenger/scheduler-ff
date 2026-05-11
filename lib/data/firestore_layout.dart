/// Reference for **Cloud Firestore** layout used by Scheduler.
///
/// **Authentication:** use **Firebase Auth** only. Do **not** store password hashes
/// (or passwords) in Firestore — Auth already stores credentials securely.
///
/// ---
/// ### `users/{uid}`
/// Profile mirror for queries and rules (Auth remains source of truth for sign-in).
/// - `email` — string (copy of Auth email)
/// - `displayName` — string (optional)
/// - `createdAt` / `updatedAt` — timestamp
///
/// ### `users/{uid}/groupMemberships/{inviteCode}`
/// Denormalized list so the client can load “my groups” without scanning all groups.
/// Doc id equals the group invite code.
/// - `groupName` — string
/// - `inviteCode` — string (same as doc id)
/// - `role` — `"owner"` | `"member"`
/// - `joinedAt` — timestamp
///
/// ---
/// ### `groups/{inviteCode}`
/// Doc id **is** the invite code (uppercase, alphabet above) → uniqueness enforced.
/// - `name` — string
/// - `inviteCode` — string (duplicate of doc id; handy for clients)
/// - `ownerId` — uid string
/// - `memberCount` — number (denormalized; increment on join)
/// - `createdAt` — timestamp
///
/// ### `groups/{inviteCode}/members/{uid}`
/// - `role` — `"owner"` | `"member"`
/// - `joinedAt` — timestamp
///
/// ---
/// ### Availability (later — compact overlap-friendly shape)
/// Store **per member per week** under the group so you can fetch one group’s grid
/// for overlap UI or Cloud Functions.
///
/// **`groups/{inviteCode}/weeks/{weekId}/avail/{uid}`**
/// - `weekId` — e.g. ISO week `"2026-W19"` or `"2026-05-05"` (Monday anchor you define)
/// - `resolutionMinutes` — e.g. `30`
/// - `slotCount` — e.g. `336` (= 7 × 48 half-hours); keep consistent app-wide
/// - `bits` — string: **Base64** of a **bit-packed** bitmap (little-endian), length
///   `ceil(slotCount / 8)` bytes — `true` = member is available in that slot  
///   Alternative: `slots` — array of int indices `[0..slotCount-1]` (sparse; bigger writes)
///
/// For **group-wide queries** (“who’s free Monday 9–10?”), either:
/// - load all `avail/{uid}` for that `weekId` on the client and intersect bits, or
/// - add a **Cloud Function** on write to maintain **`freeBuckets`** summaries.
///
/// **Note:** timezone — pick **UTC** or a stored `timezone` on the group for interpretation.
class FirestoreLayout {
  FirestoreLayout._();
}
