# Project Apple — iPhone Interruptibility Research App

A personal iOS research app that learns when I am interruptible based on 
lightweight iPhone usage behavior, timing, device context, and notification responses.

## What it does

- Tracks app open/close events for a curated set of apps via App Shortcuts
- Sends randomized interruptibility ping notifications throughout the day
- Captures passive notification behavior (opened, dismissed, ignored) as training labels
- Records device context at ping time (battery, charging, network, audio)
- Reconstructs app usage sessions from raw telemetry
- Computes behavioral feature snapshots at each ping delivery time
- Syncs all data to Firebase Firestore for analysis
- Designed to support on-device interruptibility prediction via a trained ML model

## Research goal

Build a personal ML model that predicts the best times to interrupt me — 
trained entirely on my own passive behavioral data, with no message content, 
contacts, browsing history, or location collected.

## Architecture

- **SwiftData** — local storage for telemetry events, app sessions, and feature snapshots
- **UNUserNotificationCenter** — ping scheduling and passive outcome capture
- **Firebase Firestore** — cloud sync with anonymous auth
- **FeatureBuilder** — computes one canonical feature row per ping at delivery time
- **Colab (planned)** — model training pipeline using XGBoost / Random Forest

## Feature pipeline

Each ping produces one `InterruptibilitySnapshot` with:

| Feature | Description |
|---|---|
| `hourSin` / `hourCos` | Cyclical time-of-day encoding |
| `isWeekend` | Weekday vs weekend |
| `opensLast15m` | App opens in past 15 minutes |
| `opensLast60m` | App opens in past 60 minutes |
| `switchesLast15m` | App switches in past 15 minutes |
| `timeSinceLastOpenSec` | Idle time before ping |
| `timeSinceLastPingSec` | Gap since previous ping |
| `pingsLast24h` | Ping density over past day |
| `activeTrackedAppCategory` | Currently active app at ping time |

## Label design

| Behavior | Label | Confidence |
|---|---|---|
| Explicit yes | positive | explicit |
| Explicit no / not now | negative | explicit |
| Notification body tap | positive | passive high |
| Swipe dismiss | negative | passive high |
| No response after 30min | unknown | passive soft |

Explicit responses override passive outcomes. Unknown rows are excluded from training.

## Privacy

- No message content
- No contacts
- No browsing history  
- No precise location
- Anonymous Firebase UID only

## Status

- [x] Event logging and session reconstruction
- [x] Notification ping scheduling
- [x] Passive outcome capture (opened / dismissed / ignored)
- [x] FeatureBuilder and InterruptibilitySnapshot
- [x] Firebase sync
- [ ] Colab training notebook
- [ ] Live on-device prediction
- [ ] Home / Live / Voice tab experiences

## Stack

Swift · SwiftData · Firebase Firestore · Python · Colab
