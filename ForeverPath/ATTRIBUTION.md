# Attribution

## AllTheThings Forever quest data

`Data/Quests.lua` is generated from
[ATTWoWAddon/AllTheThings](https://github.com/ATTWoWAddon/AllTheThings), pinned to
commit `ff2c55edc1bfac8a6fe739b48cee1dac245d4729`, from
every zone file under `.contrib/.db/forever/zones/` (and `constants/maps.lua` for map IDs).

Copyright (c) 2026 AllTheThings WoW Addon

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## RestedXP Guides Forever stat weights

`Data/StatWeights.lua` is generated from
[RestedXP/RXPGuides](https://github.com/RestedXP/RXPGuides),
`DB/forever/StatWeights.lua`, pinned to commit
`738f4ca077594862e96de4911977bc813c7782e5` and retrieved 2026-09-26.

The imported data is licensed under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
ForeverPath preserves source, commit, retrieval date, client applicability and
license on every generated profile. The importer includes stat facts only; it
does not copy RXP guide text.

## RestedXP Guides Forever leveling routes

`Data/Routes.lua` is generated from
[RestedXP/RXPGuides](https://github.com/RestedXP/RXPGuides),
`Guides/forever/*.lua`, pinned to commit
`5dd3a25f0248db88a1d60134d6a622eee7328674` and retrieved 2026-09-29.

The imported data is licensed under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) and is
adapted, not copied verbatim: ForeverPath keeps the route facts (which guide
follows which, quest IDs and names, NPC names, positions, expected levels and
class/race tags). World coordinates are converted to map positions with the
client's UiMapAssignment table. Step instructions and tips are not included.
Thanks to RestedXP for publishing the guides under an open license.
