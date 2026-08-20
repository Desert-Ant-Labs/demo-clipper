# Third-party notices: Clipper

Clipper's source is MIT (see [`LICENSE`](LICENSE)), and that license covers this
repository only. Everything listed below carries its own terms.

## Desert Ant Labs models and SDKs

Licensed under the **Desert Ant Labs Source-Available License, Version 1.0**.
Authoritative terms: **<https://license.desertant.com/1.0>** (machine-readable at
<https://license.desertant.com/1.0.txt>). Copyright © 2026 Desert Ant Labs B.V.
`SPDX-License-Identifier: LicenseRef-DAL-Source-Available-1.0`

In short: free below **100,000 monthly active devices per platform, per model**;
above that a commercial license is required (<licensing@desertant.com>). You may
embed the models in your application. You may **not** use the models, their
outputs, or their logs to train a competing on-device model. Apps that ship them
must credit Desert Ant Labs (<https://license.desertant.com/attribution>).

| Package | What it does here |
|---|---|
| [`desert-ant-core`](https://github.com/Desert-Ant-Labs/desert-ant-core) | The three models. `Voz` reads the speech; `Clips` picks which sentences make a clip; `Title` writes the title and description each one is posted under |

The package bundles no weights. The app reads the models from the directory
`mise run models` fills in, and each model carries its own third-party notices
for the upstream weights it was fine-tuned from.

## Desert Ant Labs brand kit

[`desert-ant-swift`](https://github.com/Desert-Ant-Labs/desert-ant-swift)
(product `DesertAntUI`) draws the mark, the loader, the colors, and the
attribution lockup. The code is MIT. The Desert Ant Labs name and mark are
trademarks, and no license here grants rights to them.

## Linked Swift packages

Versions are resolved by SwiftPM against `project.yml`; the generated project
carries the pins.

| Package | License | Copyright |
|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | Apple Inc. |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | © 2023 ml-explore |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MIT | © 2024 ml-explore |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | Apache-2.0 | © 2022 Hugging Face SAS |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | Apache-2.0 | © 2025 Hugging Face SAS |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | Apache-2.0 | © 2022 Hugging Face SAS |
| [EventSource](https://github.com/mattt/EventSource) | MIT | © 2025 Mattt |
| [yyjson](https://github.com/ibireme/yyjson) | MIT | © 2020 YaoYuan |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | MIT | © 2017-2025 Thomas Zoechling |
| [swift-asn1](https://github.com/apple/swift-asn1) | Apache-2.0 | Apple Inc. |
| [swift-atomics](https://github.com/apple/swift-atomics) | Apache-2.0 | Apple Inc. |
| [swift-collections](https://github.com/apple/swift-collections) | Apache-2.0 | Apple Inc. |
| [swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | Apple Inc. |
| [swift-nio](https://github.com/apple/swift-nio) | Apache-2.0 | Apple Inc. |
| [swift-numerics](https://github.com/apple/swift-numerics) | Apache-2.0 | Apple Inc. |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | Apache-2.0 | Apple Inc. |
| [swift-system](https://github.com/apple/swift-system) | Apache-2.0 | Apple Inc. |

Only swift-argument-parser is declared by Clipper. The rest arrive through the
model packages and are listed because they ship in the app; the MLX ones come
in because `Packages/MLXTrait` enables the core's `MLX` trait.
