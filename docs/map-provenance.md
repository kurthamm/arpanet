# ARPANET Map Provenance

The home-page map uses color to show both availability and project provenance.
This is based on the original Obsolescence Guaranteed map data from
`https://obsolescence.dev/arpa/assets/js/arpanet-nodes.js`.

## Original Project Colored Hosts

The upstream map used `scenstat` for the colored scenario hosts:

| Host | Original color | Original meaning | Site |
| ---: | --- | --- | --- |
| `#70` | Green | Accessible in original reconstruction | MIT-DMS PDP-10 ITS |
| `#134` | Green | Accessible in original reconstruction | MIT-AI PDP-10 ITS |
| `#198` | Green | Accessible in original reconstruction | MIT-ML PDP-10 ITS |
| `#11` | Green | Accessible in original reconstruction | Stanford/SU-AI PDP-10 SAIL |
| `#2` | Yellow | Expected online soon | SRI-ARC PDP-10 TENEX/NLS |
| `#69` | Yellow | Expected online soon | BBN-TENEX PDP-10 |
| `#9` | Yellow | Expected online soon | Harvard PDP-10 |
| `#1` | Yellow | Expected online soon | UCLA-NMC Sigma 7 |
| `#6` | Red | Longer-term reconstruction | MIT-MULTICS H-645 |
| `#65` | Red | Longer-term reconstruction | UCLA-CCN IBM 360/91 |

Stanford/SU-AI `#11` was not one of the first four 1969 ARPANET hosts, but it
was present on the May 1973 map and was already green in the original
reconstruction project's map data.

## Hosted 2026 Extensions

This fork keeps the original-project live hosts green even if the local
deployment improved or repaired them. Garnet is reserved for live hosts whose
status changed beyond the original project map.

Visible garnet hosts:

| Host | Site | Reason |
| ---: | --- | --- |
| `#1` | UCLA-NMC Sigma 7 | Original project yellow; this fork made it live |
| `#6` | MIT-MULTICS H-645 | Original project red; this fork made it live |
| `#65` | UCLA-CCN IBM 360/91 | Original project red; this fork made it live |

Host `#126` / HILTON-KA1 is a live hosted addition, but its original map record
uses placeholder coordinates near the upper-left corner of the image. It is
therefore hidden from the historical map overlay with `mapHidden: true` instead
of drawing a misleading bubble.

## Implementation Notes

The map data lives in `arpa/assets/js/arpanet-nodes.js`.

- `liveStatus` is this deployment's availability state.
- `origin: "original"` keeps a live node green.
- `origin: "kurt"` marks a live 2026 extension in garnet and adds the small plus badge.
- `mapHidden: true` suppresses color and badge drawing for placeholder records.

The home-page legend is in `arpanet_home.html`.
