# Window lifecycle regression checks

Run on macOS with the Command Line Tools or Xcode selected:

```sh
python3 StandaloneTests/WindowLifecycle/run.py
```

The runner uses the selected macOS SDK and the host architecture. Set `SDKROOT`
to use a different installed SDK. An optional source-root argument tests the
same production methods integrated into another checkout.

The checks extract production methods verbatim and simulate WindowServer,
accessibility notifications, and panels. They create no real windows and do not
synthesize input or change accessibility permissions. They do not replace a
manual Chrome close-button test. Results and compiler logs are written to the
printed temporary result directory.

The harness lives outside the Xcode `TabbedTests` source directory because these
boundary doubles and the executable entry point are for this standalone runner.
