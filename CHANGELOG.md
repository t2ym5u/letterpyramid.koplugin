# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-11-24

### Changed
- French accepts 1,482 more rare words when typed, taken from the Grammalecte
  lexicon (Dicollecte, MPL 2.0) through Boggle's word list. Pyramids, hints,
  revealed words and the Daily Challenge are unchanged.

## [1.0.3] - 2026-11-24

### Changed
- Picks up game-common 1.20.0: a deferred action no longer runs once the
  game is closed or a new game has started, and the game is saved a few
  seconds after a move instead of after every one, and at once on close,
  suspend or power-off.

## [1.0.2] - 2026-11-24

### Changed
- Picks up game-common 1.19.0: with the Dashboard installed, the title bar's
  close icon becomes a house that goes back to it.

## [1.0.1] - 2026-11-24

### Changed
- Picks up game-common 1.18.0: a status line cut off with "…" opens in full
  when tapped, so a long hint can be read.

## [1.0.0] - 2026-11-19

### Added
- First release: Letter Pyramid, in English and French. Three modes
  (Pyramid, Upside down, Diamond), three levels, hints, reveal, Daily
  Challenge, auto-save.
