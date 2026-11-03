# Darts Match Tracker

A containerized, single-page version of the `Wedstrijdschema darten.xlsx` workbook: a
round-robin fixture sheet for a poule of 4-8 players, with semifinals (1st vs 4th, 2nd
vs 3rd) and a final. Fixture patterns for 4, 5, 6 and 7 players are copied verbatim from
the workbook's matrices; see "Known limitations" below for 8 players.

Seeding for the top 4 is by poule wins. When two or more players are tied on wins in a
way that affects who lands in positions 1-4 (the whole top 4, or just part of it, e.g.
only 3rd/4th, or 2nd-4th), the app can't break the tie on its own — it shows a "Bull-ronde
nodig" card asking for the result of an actual bull-off, and holds the semifinal back
until that's filled in.

### Multiple poules

"Aantal poules" (1, 2, or 4) runs that many poules side by side, each with its own
round-robin schedule and names. With more than one poule, only the top 2 of each poule
advance (ties affecting 1st/2nd get the same bull-off treatment as above, just for the
top 2 instead of the top 4), and they cross into a knockout bracket instead of the
single-poule semifinal: with 2 poules, poule A's #1 plays poule B's #2 and poule B's #1
plays poule A's #2, then the two winners meet in the final; with 4 poules, the same
cross-seeding happens within each pair of poules (A/B and C/D) as a quarterfinal round
first. All poules share one poule size.

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

### Big-screen display

`http://localhost:8080/display` is a read-only, auto-rotating scoreboard meant for a TV
or projector during a competition: large type, no controls. It cycles through each
poule's standings and next match, then a slide for the knockout bracket (semis/final, or
quarterfinals too with 4 poules), polling the server every 5 seconds and advancing every
10 seconds. Both can be tuned per screen with query parameters, e.g.
`/display?interval=15&refresh=3`.

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
- Only 1, 2, or 4 poules are supported per running container (not an arbitrary count),
  so the cross-bracket stays a clean knockout. All poules in a container share one
  poule size.
