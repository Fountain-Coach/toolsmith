This directory holds seccomp and other configuration profiles used by sandbox
runners.  At runtime, the `BwrapRunner` and `QemuRunner` will load profiles
from this directory (e.g. `restricted.json`) to constrain the sandboxed
environment.

If you wish to customise the sandbox behaviour, place additional profile
files here.  See the FountainAI project for examples.