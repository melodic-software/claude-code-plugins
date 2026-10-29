---
bump: patch
---

### Fixed

- `/playwright:demo-video`: a click on a small target the camera cannot zoom in on now gets a readable ring. At zoom 1.0, a target under 120 px on its longer side gets a ring with 2.5 times the stroke width and gap. A frame edge near the target now limits only that side of the ring, not all four, and the ring never covers the target: a side with no room left runs past the frame edge and is clipped.
