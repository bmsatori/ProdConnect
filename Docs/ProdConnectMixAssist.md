# ProdConnect Mix Assist

## Product Direction

`ProdConnect Mix Assist` is a separate macOS app that works beside the main `ProdConnect` macOS app. It is not a DAW and it does not route or process house audio as a signal engine. Its role is:

- listen to one or more live audio references
- compare live program material against stored target references
- read ProdConnect context like Patchsheet, Run of Show, and Run of Show Live
- control supported consoles or DAWs over OSC, MIDI, or vendor-specific transport

Primary use case:

- church livestream mix consistency

Secondary use case:

- FOH mix assistance

## Non-Goals

- no native multitrack DAW timeline
- no native audio routing matrix
- no replacement for Pro Tools, Nuendo, or console firmware
- no unrestricted autonomous console control on day one

## Initial Architecture

The app should be decomposed into five layers:

1. `ProdConnect Context`
   Reads Patchsheet, Run of Show, Run of Show Live, team metadata, and future scene markers.

2. `Audio Capture`
   Receives analysis inputs from Dante, USB audio interfaces, or stereo line capture devices.
   This layer should expose analysis frames and channel snapshots, not act as a mixer.

3. `Reference Engine`
   Stores fingerprints for trusted mixes and trusted channel tones.
   Fingerprints should include:
   - spectral envelope
   - loudness window
   - transient profile
   - dynamics profile
   - stereo balance
   - timing / scene tags

4. `Decision Engine`
   Produces bounded recommendations or automation moves when live input deviates from a target.
   This should start in recommendation mode, then graduate to guarded automation.

5. `Control Adapters`
   Sends moves to external systems like:
   - Yamaha DM7
   - Allen & Heath consoles
   - Pro Tools
   - generic OSC targets
   - generic MIDI targets

## Implementation Sequence

### Phase 1

- separate macOS target and app shell
- shared sign-in and team-data access via `ProdConnectStore`
- launch path from `ProdConnectMac`
- live project context dashboard

### Phase 2

- reference capture model
- snapshot storage
- scene tagging tied to Run of Show
- simulation mode with no live writes

### Phase 3

- transport abstraction for OSC and MIDI
- generic adapter test harness
- console profile model
- bounded parameter writer

### Phase 4

- mix comparison engine
- tolerance windows
- recommendation UI
- operator approval workflow

### Phase 5

- guarded automation
- per-channel assist
- solo-based channel diagnosis
- EQ / gate / compressor recommendation loops

## Safety Requirements

- every write path must support dry-run mode
- every adapter must expose parameter bounds and rollback support
- every automated move must be rate-limited
- operators must be able to freeze automation instantly
- reference matching should be scene-aware to avoid forcing one mix profile onto a different song or speaker

## Pricing

Not decided yet.

For now, keep Mix Assist behind non-free access, but do not hard-code product gating until the feature and packaging are clearer.
