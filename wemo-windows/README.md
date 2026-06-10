# Wemo Dusk/Dawn Control (Windows)

Keep your discontinued Belkin Wemo switches working **without the Wemo cloud or app**.
This controls them directly over your home network and turns them **ON at dusk and
OFF at dawn**, with sunrise/sunset computed locally for ZIP 54313 (Green Bay, WI area)
— no internet connection required for daily operation.

Built with plain PowerShell + Windows Forms, so there is **nothing to install**:
it runs on any stock Windows 10/11 PC.

## Quick start

1. Copy this `wemo-windows` folder anywhere on your PC (e.g. `C:\WemoApp`).
   Keep the folder where it is afterward — the scheduler runs the scripts from here.
2. Double-click **`Wemo Control.bat`**.
3. Click **Discover**. Your Wemo switches should appear within a few seconds.
   (If one is missing, find its IP in your router's device list and use **Add by IP…**.)
4. Test it: select a switch and click **Turn ON** / **Turn OFF**.
5. Leave the **Auto** box checked for every switch you want on the dusk/dawn schedule.
6. Click **Install scheduler**. That registers a Windows scheduled task
   (`WemoDuskDawn`) that runs hidden, starts at every sign-in, and fires at
   dusk and dawn each day.

That's it. The window only needs to be opened again when you want manual control
or to change settings.

## How it works

- **Local control:** Wemo devices have a built-in UPnP/SOAP interface on the LAN
  (ports 49152–49155). Belkin shutting down the cloud doesn't affect it.
- **Dusk/dawn:** computed on your PC with the US Naval Observatory sunrise/sunset
  algorithm from latitude/longitude (defaults: 44.5897, −88.1218 for 54313),
  using **civil twilight** — the point where it's actually getting dark — and
  your PC's time zone, so daylight saving is handled automatically.
- **Catch-up:** if the PC was off or asleep at dusk/dawn, the scheduler applies
  the correct current state as soon as it starts or wakes.

## Settings

Configuration lives in `%APPDATA%\WemoDuskDawn\config.json` (created on first run):

| Field | Meaning |
|---|---|
| `latitude` / `longitude` | Your location (defaults are for ZIP 54313). |
| `twilight` | `civil` (default), `official` (exact sunset), or `nautical` (darker). |
| `duskOffsetMinutes` | Shift the ON time. `-15` = 15 min before dusk. |
| `dawnOffsetMinutes` | Shift the OFF time. `30` = 30 min after dawn. |
| `devices[].automate` | Same as the Auto checkbox in the app. |

Edit with Notepad while the app is closed; the scheduler picks changes up
automatically. Activity is logged to `%APPDATA%\WemoDuskDawn\scheduler.log`.

## Google Home integration (optional)

The `matter-bridge` folder contains a bridge that makes your Wemo switches show
up in **Google Home** as Matter smart plugs — app tiles, "Hey Google, turn on
the porch light", routines. It runs locally on this PC; no Wemo cloud involved.

**Requirements:**
- A Matter-capable Google hub on your network: any Nest Hub, Nest Mini/Audio,
  Nest Wifi Pro, or similar Google speaker/display.
- [Node.js LTS](https://nodejs.org) installed on the PC (free, one time).
- Your switches already discovered in the control app (the bridge reads the
  same device list).

**Setup:**
1. Double-click **`Matter Bridge.bat`**. The first run downloads its library
   (needs internet once), then prints a **QR code** in the console.
2. In the Google Home app on your phone: **+ → Add device → Matter device**,
   then scan the QR code (or type the printed manual pairing code). Your
   switches appear as plugs — rename or move them to rooms as you like.
3. Close the console window, then double-click **`Install Matter Bridge.bat`**.
   From now on the bridge runs hidden in the background at every sign-in.
   (`Remove Matter Bridge.bat` undoes this.)

Google Home tiles stay in sync with reality — manual presses on the switch and
the dusk/dawn scheduler are picked up within ~20 seconds. The dusk/dawn schedule
keeps working independently; the bridge is purely additive.

**Notes:**
- Pairing only needs to be done once; the bridge remembers it in
  `%APPDATA%\WemoDuskDawn\matter-storage`. The bridge log is
  `%APPDATA%\WemoDuskDawn\matter-bridge.log`.
- If you add or remove switches later, restart the bridge (sign out/in, or
  run `Install Matter Bridge.bat` again) so Google Home sees the change.
- If pairing fails, make sure the PC and the Google hub are on the same
  network and that IPv6 isn't disabled on your router/Wi-Fi (Matter needs
  local IPv6, which is on by default on home networks).
- As with the scheduler, the PC must be running for Google control to work.

## Important notes

- **The PC must be on (or asleep-then-woken) for switching to happen.** A PC that's
  shut down at sunset can't send the ON command until it next starts. If you use
  sleep, the catch-up logic fixes the lights within a couple of minutes of waking.
- Give your Wemo switches **DHCP reservations** in your router so their IPs never
  change. Old Wemo firmware is flaky about rejoining Wi-Fi after power outages;
  a fixed IP makes them much easier to reach.
- Switches must be on the **same network/subnet** as the PC (2.4 GHz Wi-Fi).

## Troubleshooting

- **Discover finds nothing:** some routers block multicast between Ethernet and
  Wi-Fi. Use **Add by IP…** instead — it talks to the switch directly.
- **Switch shows Unreachable:** power-cycle the Wemo, confirm its IP in the router,
  re-add it. The app automatically tries all four known Wemo ports.
- **Scheduler install fails:** right-click `Install Scheduler.bat` → *Run as administrator*.
- **Did it fire last night?** Check `%APPDATA%\WemoDuskDawn\scheduler.log`.
