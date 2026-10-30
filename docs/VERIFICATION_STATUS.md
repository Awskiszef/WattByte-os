# Verification status words

Several pages say how far a claim has been checked ("TESTED", "BLOCKED", ...). The words mean the same everywhere, from the weakest claim to the strongest.

| Word | Meaning |
|---|---|
| IMPLEMENTED | The code exists. Nothing has shown that it works. |
| TESTED | Covered by automated tests on this tree (unit, widget or API tests). |
| BUILD VERIFIED | The named build command succeeded (for example `flutter build apk --debug`). It says the code compiles, not that it behaves. |
| INTEGRATION VERIFIED | Exercised against real dependencies: PostgreSQL, the live API, the generated client talking to it. |
| SIMULATOR VERIFIED | Observed on the iOS Simulator or an Android emulator. |
| DEVICE VERIFIED | Observed on a physical phone. |
| NOT VERIFIED | Implemented, but not checked in any of the ways above. |
| BLOCKED | Could not be checked because something outside the code is missing: a device, an account, a signing key, a service. |

A skipped test is never a passed test: a job or a suite that did not run is reported as not run, with the reason.
