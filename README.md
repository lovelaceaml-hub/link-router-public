# Link Router

A macOS link picker that can open URLs in local browsers and Chrome profiles. Optional rules route a host and its subdomains to a selected target. The portable default opens Chrome with its normal profile behavior and starts with no host rules.

Run `./build.sh` on macOS with the Xcode Command Line Tools. The bundle is written to `build/LinkRouter.app`. The build does not install it, launch it, change your default browser, or create a background job. To use it, open the built app and choose your own settings in its menu.

Configuration is local at `~/Library/Application Support/LinkRouterPortable/config.json`. Keep browser-profile data and private routing rules there.

[Current status](docs/HANDOFF.md)
