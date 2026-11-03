# Darts Match Tracker

A containerized, single-page version of the `Wedstrijdschema darten.xlsx` workbook: a
round-robin fixture sheet for a poule of 4-8 players, with semifinals (1st vs 4th, 2nd
vs 3rd) and a final. Fixture patterns for 4, 5, 6 and 7 players are copied verbatim from
the workbook's matrices; see "Known limitations" below for 8 players.

## Build and run

```bash
docker build -t darts-tracker .
```

```bash
docker run -d --name darts-tracker -p 8080:8080 -v darts-data:/data darts-tracker
```

Open `http://localhost:8080`. State (player names, results, and tournament history) is
stored in the `darts-data` volume at `/data/state.json` and shared with everyone who
opens the page. Use "Download backup" in the header to save a copy of the current state
as a JSON file. The page can also be added to a phone's home screen (it ships a web app
manifest and icons for this).

### Read-only mode and login

Set `EDITOR_PASSWORD` when starting the container to make the page read-only for anyone
who hasn't logged in with that password:

```bash
docker run -d --name darts-tracker -p 8080:8080 -v darts-data:/data \
  -e EDITOR_PASSWORD=yourpassword darts-tracker
```

Everyone can still view the page and download backups. "Log in to edit" in the header
unlocks the names, results, reset, and history controls for that browser (via a
session cookie) until they log out. Leave `EDITOR_PASSWORD` unset to keep the previous
behavior, where anyone can edit.

To reset a tournament, stop the container and remove the volume:

```bash
docker rm -f darts-tracker
docker volume rm darts-data
```

## Known limitations

- **8-player pools**: the workbook's own "POULE VAN 8" sheet never had its fixture
  matrix (columns W.1-W.7) filled in, and the "POULE VAN 8 OLD" sheet uses a different,
  conflicting match order. There's no single authoritative 8-player sequence to copy, so
  the app generates a valid round-robin schedule algorithmically instead (every pair
  plays exactly once across 7 rounds) — it does not reproduce either workbook sheet's
  match order.
- **4-player pools**: the workbook's "POULE VAN 4" sheet actually models *two* separate
  4-player pools (named KOP/MUNT after a coin toss) whose winners and runners-up cross
  over into the semifinal. This app models a single pool of 4 with the same top-4
  reseed semifinal used for 5-7 players, which is a simpler format than the workbook's.
- Only one poule can be tracked per running container (one shared `state.json`). Running
  multiple simultaneous poules (e.g. the workbook's dual KOP/MUNT pools) needs one
  container instance per poule.
