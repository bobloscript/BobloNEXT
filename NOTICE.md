# NOTICE

## Project provenance

BobloNEXT is a new project maintained under the **bobloscript** GitHub account.

Its initial technical direction is based on the following upstream projects:

### Vind Ui Reborn / VVind-UI

Author / maintainer: **Skinny-yz**

Repository:
https://github.com/Skinny-yz/VVind-UI

BobloNEXT uses Vind Ui Reborn as a direct upstream reference and intends to retain attribution for work originating from that project.

### WindUI

Author / maintainer: **Footagesus**

Repository:
https://github.com/Footagesus/WindUI

WindUI is part of the upstream lineage referenced by this project. WindUI is distributed under the MIT License. A copy of the WindUI MIT license is included as `LICENSE-WINDUI`.

## Attribution policy

Do not remove upstream credits from this repository when redistributing BobloNEXT or substantial portions derived from the upstream projects.

Runtime branding such as `NullUI` or `VVind` may be replaced by `BobloNEXT` as the project evolves; this does not remove or replace the attribution above.

## License note

As of the initial BobloNEXT repository setup, the public VVind-UI repository does not expose a license file or GitHub-recognized license. BobloNEXT therefore does not make a blanket relicensing claim over VVind-specific additions.

The MIT license included in `LICENSE-WINDUI` applies to WindUI-originated material under the terms stated there.


## Embedded icon lookup tables

BobloNEXT embeds its icon name -> Roblox asset ID lookup tables directly into `src.lua` so the UI does not fetch those tables from another repository at runtime.

The exact tables were taken from the runtime asset mirror previously used by Vind Ui Reborn:

- **NullUI-Assets** — Skinny-yz  
  https://github.com/Skinny-yz/NullUI-Assets

That repository states that the icon lookup tables were mirrored from:

- **Nebula-Softworks/Nebula-Icon-Library**  
  https://github.com/Nebula-Softworks/Nebula-Icon-Library

The Nebula icon-library repository declares **Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)**. A copy is included as `LICENSE-NEBULA-ICONS`.

The tables contain icon names and Roblox asset IDs only. BobloNEXT does not contain the underlying icon image binaries; the referenced images remain hosted by Roblox under their asset IDs.

## Runtime dependency policy

BobloNEXT must not hardcode runtime downloads from VVind, NullUI-Assets, WindUI, or other upstream repositories.

Optional user-configured network features (for example a webhook URL, CloudService backend, AI provider endpoint, or Spotify artwork URL supplied by a configured bridge) are features, not hidden upstream dependencies.
