# Changelog

All notable changes to Scanly are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-18 (Milestone 1: Foundation)

### Added
- Flutter project for Android and iOS (`com.scanly.app`), iOS 15.5+, Android API 24+.
- Navy/neutral design system with light, dark and system themes.
- Bottom navigation with Home, Files, Search, Settings and a prominent Scan action.
- Home screen with greeting, search launcher, scan card, folders, favorites and recents.
- Files screen with folders, favorites filter, sorting, grid/list layouts and
  multi-select (favorite, move, delete).
- Folder creation, renaming, recoloring and deletion (documents are kept).
- Document viewer that shows stored page images with swipe and pinch-to-zoom.
- Local search over titles, folder names and OCR text using SQLite FTS5, with
  Bengali-aware tokenization and highlighted snippets.
- Settings for theme, scan quality, compression, PDF page size/orientation, OCR language
  and auto-OCR; privacy and about screens; storage usage; clear all data.
- Drift database with foreign keys, cascading deletes and indexes.
- App-private file storage with atomic writes, path safety and startup recovery.
- Unit and widget test suites (42 tests).

### Not yet available
- Camera scanning (Milestone 2/3), editing, PDF export, OCR.
