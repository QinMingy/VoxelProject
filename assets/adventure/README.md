# Adventure loot source models

Selected **KayKit** assets by **Kay Lousberg** (<https://kaylousberg.com/>), acquired on 2026-11-07 for the excavation prototype. Each source pack explicitly licenses its covered assets under **CC0 1.0 Universal**. The original creator license files are preserved beside the models.

Only selected free-tier assets are included. No paid EXTRA or SOURCE files were acquired. These are original polygon meshes used as sources for the game's voxel conversion, not parameterized shape recipes.

| Included model | Original asset | Official source | Preserved license |
| --- | --- | --- | --- |
| `chest.glb` | `addons/kaykit_dungeon_remastered/Assets/gltf/chest.glb` | [Dungeon Remastered 1.0](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0/tree/b0ca9bd96a8072ab36a3a5464f00ed1e06a16d07), commit `b0ca9bd96a8072ab36a3a5464f00ed1e06a16d07` | `DUNGEON_LICENSE.txt` |
| `shield.glb` | `Assets/gltf/shield_A.gltf` | [Fantasy Weapons Bits 1.0 — Free](https://kaylousberg.itch.io/fantasy-weapons-bits), `KayKit_FantasyWeaponsBits_1.0_FREE` | `WEAPONS_LICENSE.txt` |
| `warhammer.glb` | `Assets/gltf/hammer_A.gltf` | [Fantasy Weapons Bits 1.0 — Free](https://kaylousberg.itch.io/fantasy-weapons-bits), `KayKit_FantasyWeaponsBits_1.0_FREE` | `WEAPONS_LICENSE.txt` |
| `spellbook.glb` | `addons/kaykit_character_pack_adventures/Assets/gltf/spellbook_closed.gltf` | [Adventurers 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/tree/672074b73ba276876a19e8816ecdc5241817ab47), commit `672074b73ba276876a19e8816ecdc5241817ab47` | `ADVENTURERS_LICENSE.txt` |

The chest GLB is copied byte-for-byte from its pinned official repository. The other three GLBs only repack the original glTF, binary buffer and PNG atlas into single files; geometry, UVs, transforms and texture pixels are unchanged. Shield and hammer use the original `weapons_bits_texture.png`; the book uses `mage_texture.png`. All texture images are embedded, with no external resource dependency.

The downloaded official Free weapon ZIP has SHA256:

```text
1017144f85a994f405b731befa71ced360f5b60ed0b9c00c72e711c1633ce2d2
```

Included model SHA256 values:

```text
f72fd2201cd42ad399928a0b7bcc34d5b0e6d0624aeaf824fef81852109955f8  chest.glb
76357453093b4161eae4dbc6cd51aba817df4d91a8e559ff57a4d7903cccc379  shield.glb
27272721668bb037df7064235e5ab40b6581bb6d5845a732f076d5a5ceb5f333  warhammer.glb
4e33b16f33769711d159fc6e1878f4e91a59712d2e2d2d67a2f9f5ecb54d159c  spellbook.glb
```

Approximate source scene bounds before the game's own scale/rotation:

| Model | Size X × Y × Z (metres) | Placement note |
| --- | --- | --- |
| Chest | 1.700 × 1.300 × 1.446 | Two meshes; the lid is a child translated by `(0, 0.5, -0.564883)`. Apply the full node hierarchy when sampling. |
| Shield | 0.773 × 0.980 × 0.233 | One node, identity transform; the back/handle contributes to thickness. |
| Warhammer | 0.814 × 1.139 × 0.448 | One node, identity transform; the handle is narrower than the head. |
| Spellbook | 0.293 × 0.575 × 0.427 | One node, identity transform; a larger gameplay scale can preserve the cover/page silhouette. |

The embedded model units and bounds are source data, not gameplay value, backpack footprint or final excavation size. Those are configured separately by the demo.
