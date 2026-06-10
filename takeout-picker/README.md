# Where To, Tonight? 🍴

A dinner picker for two — covering the greater Green Bay, WI area with an
optional Appleton / Fox Cities area toggle.

## How to use

It's a single self-contained file: open `index.html` in any browser
(or host it anywhere static, e.g. GitHub Pages / Cloudflare Pages) and
add it to your phone's home screen.

First launch walks you through a short setup quiz: your names, whether to
include Appleton, the cuisines you both love (or never want), your typical
budget, and starring any current favorites.

## How it learns

Every interaction nudges the picker:

| You do this                     | Effect                                        |
| ------------------------------- | --------------------------------------------- |
| "Sounds good — let's do it!"    | Restaurant and its cuisine get a boost         |
| "Show another"                  | Just rerolls (won't repeat the same night)     |
| "Not our thing"                 | Restaurant hidden, cuisine slightly penalized  |
| Post-visit "Loved it"           | Big boost for that place and cuisine           |
| Post-visit "Not again soon"     | Big penalty                                    |

Recently picked places are heavily down-weighted for a week or two so you
get variety. All data lives in `localStorage`; the Settings tab has
export/import so you can sync between phones, plus a way to re-run the
setup quiz or reset entirely.

You can add, edit, and hide places on the Places tab — the ~50 built-in
restaurants are just a starting point.
