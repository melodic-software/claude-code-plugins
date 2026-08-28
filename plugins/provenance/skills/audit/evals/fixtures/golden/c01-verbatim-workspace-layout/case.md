# Where our builds put their intermediate files

Notes for anyone debugging a slow build on this repository.

Widget Runner writes every artifact it produces beneath a single workspace root, and it will not
write outside that root even when a task asks it to. The root holds four directories, each
created on first use: `cache` for content-addressed task outputs, `logs` for per-task stdout and
stderr, `locks` for the advisory files that keep two runners off one workspace, and `tmp` for
scratch space that is cleared at the start of every run.

We have never needed to move the root, so the defaults above are what you will find on every
agent in the pool.
