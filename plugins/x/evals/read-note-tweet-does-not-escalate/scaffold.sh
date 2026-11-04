#!/usr/bin/env bash
# A saved xtomd /api/fetch result (raw fields) for one long, complete note tweet: isNoteTweet true,
# a large integer reply count, no numbered markers, no mid-thought ending. Nothing for step 2.
set -euo pipefail
mkdir -p notes
cat >notes/xtomd-fetch-2015883857489522876.json <<'JSON'
{
  "id": "2015883857489522876",
  "author": {
    "name": "Quayside Tide Watch",
    "username": "fakehandle"
  },
  "createdAt": "2026-10-26T18:04:11.000Z",
  "isNoteTweet": true,
  "text": "Why the harbor gauge read 40 cm high all week, and what we changed.\n\nThe gauge on the north pier measures the water level with a radar sensor pointed down at a still-well, a pipe that damps the waves. On Monday the readings jumped 40 cm and stayed there. The tide tables did not change, the river was low, and the neighboring gauge at the lock agreed with the tables, so the sea had not moved. Our gauge had.\n\nThe cause was a gull's nest. Two of them had built on the grating over the still-well, and the radar was ranging to the top of the nest instead of the water. Every reading was the distance to twigs, minus a constant, so the error was steady and believable. Nothing in the data looked like a fault.\n\nWhat we changed: the grating now has a cone over it that birds cannot sit on, the gauge raises an alarm when it disagrees with the lock gauge by more than 15 cm for an hour, and the readings from Monday to Friday are flagged in the public record rather than deleted, so anyone using them knows why they are wrong.\n\nThe nest has been moved to the old signal mast with the harbor master's blessing. Both gulls are fine and noticeably less interested in our equipment.",
  "rawText": "Why the harbor gauge read 40 cm high all week, and what we changed. The gauge on the north pier measures the water level with a radar sensor pointed down at a still-well, a pipe that damps the waves. On Monday the readings jumped 40 cm and stayed there. The tide tables did not change, the river was low, and the neighboring gauge at the lock agreed with the tables, so the sea had not moved. Our gauge had. The cause was a gull's nest. Two of them had built on the grating over the still-well, and the radar was ranging to the top of the nest instead of the water. Every reading was the distance to twigs, minus a constant, so the error was steady and believable. Nothing in the data looked like a fault. What we changed: the grating now has a cone over it that birds cannot sit on, the gauge raises an alarm when it disagrees with the lock gauge by more than 15 cm for an hour, and the readings from Monday to Friday are flagged in the public record rather than deleted, so anyone using them knows why they are wrong. The nest has been moved to the old signal mast with the harbor master's blessing. Both gulls are fine and noticeably less interested in our equipment.",
  "media": [],
  "quoteTweet": null,
  "replies": 214,
  "retweets": 88,
  "likes": 1930
}
JSON
