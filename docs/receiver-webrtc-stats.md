# Receiver WebRTC statistics (windows_SonicRelay issue #31 companion)

The viewer collects receiver-side WebRTC statistics so packet-loss reports can
be correlated with the Windows publisher's counters (its pacing/drop/encoder
diagnostics — see `windows_SonicRelay/docs/audio-resilience.md`). Together the
two sides distinguish real network loss from late packets, publisher bursts,
and local drops.

## Collected counters

`RtcInboundAudioStats` (parsed from the audio `inbound-rtp` stats report each
poll, every 2 s while connected):

```text
packetsReceived        packetsLost           packetsDiscarded
fecPacketsReceived     concealedSamples      concealmentEvents
totalSamplesReceived   jitterBufferDelay     jitterBufferTargetDelay
jitterBufferEmittedCount
```

The transport mode (Direct/Relay), RTT, and inbound jitter were already
collected from the `candidate-pair` report. Only numbers and candidate *types*
leave the stats layer — never SDP or candidate bodies.

## Derived interval metrics

`WebRtcReceiverService.refreshStats()` keeps the previous poll's cumulative
counters per peer connection and derives interval metrics from the deltas, so
they describe recent behavior instead of a lifetime average:

```text
packetLossPercent      = ΔpacketsLost / (ΔpacketsReceived + ΔpacketsLost) * 100
concealmentPercent     = ΔconcealedSamples / ΔtotalSamplesReceived * 100
jitterBufferDelayMs    = ΔjitterBufferDelay / ΔjitterBufferEmittedCount * 1000
```

Deltas are clamped at zero (stats resets on renegotiation/SSRC change must not
produce negative intervals), and a metric is null when its counters are absent
or the interval carried no traffic. The previous-counters snapshot is reset
whenever the peer connection is replaced or torn down.

The results land in `ListenerStats` (alongside the cumulative counters) and
the recent packet-loss percentage is shown on the listener page's Quality
card next to latency and jitter.

## Reading the numbers

- `packetLossPercent` high, publisher drop counters flat → real network loss;
  check whether it correlates with `Relay` transport or a specific Wi-Fi band.
- `concealmentPercent`/`packetsDiscarded` growing while `packetsLost` is
  mostly flat → packets arrive too late for the jitter buffer (jitter, or a
  bursty sender).
- `jitterBufferDelayMs` growing → the buffer is stretching to absorb jitter;
  latency rises before audio breaks.
- `fecPacketsReceived` only counts when the publisher profile actually emits
  in-band FEC (SILK/hybrid — the mono voice profile); the stereo music
  profiles conceal with PLC instead.
