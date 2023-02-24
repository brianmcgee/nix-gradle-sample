## Overview

This repository contains some examples of how to package [Gradle](https://gradle.org/) based applications using [Nix](https://nixos.org).

For an overview of what is provided run `nix flake show`:

```shell
├───apps
│   ├───aarch64-linux
│   └───x86_64-linux
├───checks
│   ├───aarch64-linux
│   │   └───treefmt: derivation 'treefmt-check'
│   └───x86_64-linux
│       └───treefmt: derivation 'treefmt-check'
├───devShells
│   ├───aarch64-linux
│   │   └───default: development environment 'devshell'
│   └───x86_64-linux
│       └───default: development environment 'devshell'
├───formatter
│   ├───aarch64-linux: package 'treefmt'
│   └───x86_64-linux: package 'treefmt'
├───legacyPackages
│   ├───aarch64-linux omitted (use '--legacy' to show)
│   └───x86_64-linux omitted (use '--legacy' to show)
├───nixosConfigurations
├───nixosModules
├───overlays
└───packages
    ├───aarch64-linux
    │   ├───fod: package 'fod-1.0.0'
    │   ├───gradle2nix: package 'gradle2nix-1.0.0'
    │   └───yolo: package 'yolo-1.0.0'
    └───x86_64-linux
        ├───fod: package 'fod-1.0.0'
        ├───gradle2nix: package 'gradle2nix-1.0.0'
        └───yolo: package 'yolo-1.0.0'
```
To execute the sample packages you can run:

- `nix run fod` for the vanilla fixed-output derivation approach.
- `nix run gradle2nix` for the [Gradle2nix](https://github.com/numtide/gradle2nix) based approach
- `nix run yolo` for the escape hatch based *"I just can't this to fucking work"* approach.

