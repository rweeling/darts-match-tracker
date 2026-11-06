<p align="center">
  <img src="favicon.svg" alt="Darts Match Tracker logo" width="84">
</p>

<h1 align="center">Darts Match Tracker</h1>

<p align="center">
  A local-network web app that turns darts tournament night into a guided scoreboard —
  fill in players, click winners, and the schedule, bracket, and stats take care of
  themselves.
</p>

<p align="center">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-brightgreen">
  <img alt="Python 3.12+" src="https://img.shields.io/badge/python-3.12%2B-blue">
  <img alt="Dependencies: stdlib only" src="https://img.shields.io/badge/dependencies-stdlib%20only-informational">
  <img alt="Deploy: Docker" src="https://img.shields.io/badge/deploy-docker-2496ED">
</p>

## Contents

- [Features](#features)
- [Multiple pools](#multiple-pools)
- [How to use it](#how-to-use-it)
- [Build and run](#build-and-run)
  - [Big-screen display](#big-screen-display)
  - [Read-only mode and login](#read-only-mode-and-login)
- [Known limitations](#known-limitations)
- [License](#license)
- [Contributors](#contributors)

A containerized, single-page darts tournament tracker: a round-robin fixture schedule
for a pool of 4-8 players, with semifinals (1st vs 4th, 2nd vs 3rd) and a final.
Fixture patterns for 4, 5, 6, and 7 players follow a fixed match order; 8-player pools
use an algorithmically generated schedule instead (see "Known limitations" below).
Within each pool, matches are ordered to avoid the same player playing two matches
back to back wherever the schedule allows it (for 4 and 5 players, one such pairing is
mathematically unavoidable with so few matches per round).

Seeding for the top 4 is by pool wins. When two or more players are tied on wins in a
way that affects who lands in positions 1-4 (the whole top 4, or just part of it, e.g.
only 3rd/4th, or 2nd-4th), the app can't break the tie on its own — it shows a "Bull-off
needed" card asking for the result of an actual bull-off, and holds the semifinal back
until that's filled in.

## Features

- Round-robin pools (4-8 players, 1/2/4/6/8/10 pools) feeding a seeded knockout
  bracket, with bull-off tie-breaks when pool standings don't resolve on their own.
- Live 180 and high-finish (75+) tracking per player, editable and mergeable (for
  when the same person got entered under two different names).
- A "Previous winners" leaderboard across tournaments, with the same merge tooling.
- An auto-rotating, read-only **big-screen display** for a TV or projector, with its
  own light/dark theme and an on-screen confetti celebration whenever a 180 or a high
  finish is recorded.
- Light and dark themes on both the editor and the display, remembered per browser.
- One-file JSON backup/import, and optional password-gated editing with everyone
  still able to view.
- Installable as a home-screen app on a phone (ships a web app manifest).

### Multiple pools

"Number of pools" (1, 2, 4, 6, 8, or 10) runs that many pools side by side, each with
its own round-robin schedule and names. With more than one pool, only the top 2 of
each pool advance (ties affecting 1st/2nd get the same bull-off treatment as above,
just for the top 2 instead of the top 4), and they cross into a knockout bracket
instead of the single-pool semifinal: with 2 pools, pool A's #1 plays pool B's #2 and
pool B's #1 plays pool A's #2, then the two winners meet in the final; with 4 pools,
the same cross-seeding happens within each pair of pools (A/B and C/D) as a
quarterfinal round first. All pools share one pool size.

With 6, 8, or 10 pools there are 12, 16, or 20 qualifiers — not a clean power of 2 —
so the bracket is seeded with "byes": the strongest-seeded qualifiers (pool winners
first, then runners-up, in pool order) sit out the first knockout round and advance
straight through, while the rest play it out. This keeps the #1 and #2 overall seeds
apart until the final, same as a standard seeded tournament bracket. With 8 pools the
qualifier count (16) is already a clean power of 2, so there are no byes.

## How to use it

This is the website your club opens on match night to keep score. Here's what to do,
in plain terms:

1. **Open the page** in a browser (on a laptop, tablet, or phone) at the address your
   club gives you — e.g. `http://192.168.x.x:8080`, or whatever address was set up.
2. **Fill in the player names** for each pool, under "Player names". These save
   automatically as you type — no save button needed.
3. **As each match finishes**, find that match in the schedule grid and pick the
   winner from the dropdown in that cell. Everyone's win count and the knockout
   bracket update themselves right away.
4. **During a match, log the highlights**: switch to the "Statistics" tab and tap
   "180 thrown" whenever someone throws a 180, or type a score of 75 or higher into
   the finish box and tap "Add" for a big finish. These lists keep running all
   season, even after you reset for a new tournament. If the same player ended up
   split across two names (a typo, say), use "Merge into…" on either the 180 tally
   or the "Previous winners" list to combine their totals.
5. **If the top spots end up tied**, the app will show a "Bull-off needed" card
   asking for a real bull-off to settle the order — just fill in who came out on top.
6. **When the final is played**, pick the winner and press the button to save it to
   "Previous winners" and start a fresh night.
7. **Put the big screen up**: open `/display` (e.g. `http://192.168.x.x:8080/display`)
   on the TV or projector — it's read-only and cycles through standings and matches on
   its own, nothing to click.
8. There's a **"Download backup" button** in the header if someone wants a copy of
   the current data saved to a file, and a light/dark theme toggle next to it. The
   **"Import backup" button** next to it does the reverse: pick a previously
   downloaded backup file and it replaces everything currently on the page, after
   a confirmation step. Import needs "Log in to edit" first, same as other changes.

If logins are turned on for your club, anyone can look at the page, but editing names,
results, and history needs "Log in to edit" in the header first.

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
manifest for this).

As a safety net, the server also keeps `state.json.bak` in that same volume: a copy of
the state from just before the most recent save, in case a save goes wrong (for example
an accidental "Import backup" of the wrong file). There's no restore button for it — it
can only be put back by someone with access to the volume, by copying it over
`state.json` and restarting the container.

### Big-screen display

`http://localhost:8080/display` is a read-only, auto-rotating scoreboard meant for a TV
or projector during a competition: large type, no controls. It cycles through each
pool's standings and next match, then a slide for the knockout bracket (semis/final, or
quarterfinals too with 4 pools), polling the server every 5 seconds and advancing every
10 seconds. Both can be tuned per screen with query parameters, e.g.
`/display?interval=15&refresh=3`. Once every pool has finished its round-robin, the
pool-standings slides drop out on their own and it shows only the knockout bracket.

It has its own light/dark theme toggle (a small button in the top-right corner,
independent of the editor's) and celebrates live: whenever a 180 or a high finish gets
logged on the editor, the display picks it up on its next poll and runs a short
confetti burst with the player's name — gold for a 180, teal for a high finish — so the
room knows what just happened without anyone glancing at a phone.

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

The container itself serves plain HTTP, with no TLS. If it's reachable from anywhere
other than a trusted local network, put it behind a reverse proxy (nginx, Caddy,
Traefik, etc.) that terminates HTTPS — otherwise the password and session cookie
travel in plaintext.

To reset a tournament, stop the container and remove the volume:

```bash
docker rm -f darts-tracker
docker volume rm darts-data
```

## Known limitations

- **8-player pools** use an algorithmically generated round-robin schedule rather than
  a fixed match-order table (every pair plays exactly once across 7 rounds), unlike the
  fixed patterns used for 4-7 players.
- Only 1, 2, 4, 6, 8, or 10 pools are supported per running container (not an
  arbitrary count). 6 and 10 pools use a seeded knockout bracket with byes (see
  "Multiple pools" above) rather than a clean power-of-2 bracket. All pools in a
  container share one pool size.

## License

MIT — see [LICENSE](LICENSE).

## Contributors

- Ramon Weeling ([@rweeling](https://github.com/rweeling))
- Claude (Anthropic) — AI pair-programming assistant
