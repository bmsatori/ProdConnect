## TestFlight Notes

This build includes a large Run of Show, NDI, MIDI, Freshservice, and asset-management update.

### New in this build

- Run of Show now includes a full **Stage Plot** mode with drag-and-drop positioning, rotation, stage-shape options, quick role presets, and editable labels/subtitles for performers and gear.
- Added **Run of Show Stage Plot as an NDI feed source** on Mac, alongside expanded NDI feed options for Run of Show content.
- Added **Run of Show Live MIDI control** on Mac with configurable mappings for Start/Restart, Previous, Next, and Reset, plus MIDI device selection and learn/save behavior.
- Added **auto-start support for Run of Show Live** based on scheduled start time.

- Added broader **NDI workflow improvements**:
  - Patchsheet rows can now track **NDI enabled** state more cleanly.
  - Added bulk NDI enable/disable controls for filtered patchsheet results on Mac.
  - Patchsheet export now includes the **NDI Enabled** field.
  - Mac builds now bundle the NDI runtime/license files and include the local-network/Bonjour setup needed for NDI publishing.

- Added **patchsheet ordering and export improvements**:
  - Patch rows now preserve explicit position/order.
  - Added move/reorder controls on Mac.
  - Patchsheet CSV import/export handling is more complete, including notes, room, and NDI fields.

- Added **asset room support** across the app:
  - Gear items now have a dedicated **Room** field.
  - Room can be edited when creating or updating gear.
  - Room is included in asset import/export flows and team data persistence.

- Added and tuned **Freshservice asset import**:
  - Better compatibility with both legacy and newer Freshservice asset endpoints.
  - Added location and asset-type lookup resolution so imports map IDs to readable names.
  - Improved asset detail fetching and fallback behavior.
  - Better handling for large imports, pagination, deduping, and rate limits.
  - Expanded imported asset mapping for room, serial number, vendor/purchased from, purchase date, cost, status/state, and related metadata.

- Added further **Freshservice ticket import tuning** and downstream mapping cleanup for imported ticket fields and attachments.

- Added **CSV parsing improvements** for imports so quoted values, embedded commas, header normalization, and mixed field names are handled more reliably.

- Added **asset management reliability fixes**:
  - Team code is now enforced more consistently when saving/replacing gear.
  - Bulk gear deletion now deletes the team’s actual Firestore records more safely and restores listeners/cache cleanly afterward.
  - Room/location lists are persisted as new values are imported or edited.

- Added **security/rules updates** so create/update checks validate that edited documents still belong to the signed-in user’s team across lessons, checklists, ideas, tickets, channels, gear, patchsheet, and run-of-show documents.

- Added a new admin utility script: `scripts/delete_team_gear.js`.

### What To Test

- Build a Run of Show, switch to **Stage Plot**, add items, drag/rotate them, and confirm layout saves correctly.
- On Mac, create or edit **NDI feeds** for Patchsheet, Run of Show Live, and Stage Plot.
- On Mac, test **MIDI control** for Run of Show Live using an external MIDI device.
- Import assets and tickets from **Freshservice** and verify rooms, locations, types, statuses, and other mapped fields come across correctly.
- Export Patchsheet and Gear CSVs and confirm the new **Room**, **Notes**, and **NDI Enabled** fields are included where expected.
