// bridge.js - Matter bridge that exposes local Wemo switches to Google Home.
//
// Reads the switch list from the shared WemoDuskDawn config
// (%APPDATA%\WemoDuskDawn\config.json) and presents each one as a Matter
// smart plug. Pair it once with the Google Home app (QR code is printed on
// first run) and the switches show up as normal devices: app tiles, voice
// control, routines. Everything stays on your local network.
//
// Run with:  node bridge.js   (or use the .bat launchers one level up)

import { readFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

import { Endpoint, Environment, Logger, ServerNode, VendorId } from "@matter/main";
import { BridgedDeviceBasicInformationServer } from "@matter/main/behaviors/bridged-device-basic-information";
import { OnOffPlugInUnitDevice } from "@matter/main/devices/on-off-plug-in-unit";
import { AggregatorEndpoint } from "@matter/main/endpoints/aggregator";
import { QrCode } from "@matter/main/types";

import { getBinaryState, setBinaryState } from "./wemo.js";

const POLL_SECONDS = 20;

// Keep matter.js's own logging down to warnings; our messages use console directly.
Logger.level = "warn";

// --- shared config (same file the PowerShell app uses) ----------------------

const appData = process.env.APPDATA ?? join(process.env.HOME ?? ".", ".config");
const configDir = join(appData, "WemoDuskDawn");
const configPath = join(configDir, "config.json");

function loadDevices() {
    if (!existsSync(configPath)) {
        console.error(`No config found at ${configPath}.`);
        console.error(`Run "Wemo Control.bat" first and click Discover so your switches are saved.`);
        process.exit(1);
    }
    // Strip a UTF-8/UTF-16 BOM if PowerShell wrote one.
    const raw = readFileSync(configPath, "utf8").replace(/^﻿/, "");
    const devices = (JSON.parse(raw).devices ?? []).filter(d => d.ip);
    if (devices.length === 0) {
        console.error("Config has no switches yet. Run 'Wemo Control.bat' and click Discover first.");
        process.exit(1);
    }
    return devices;
}

const devices = loadDevices();

// --- matter node -------------------------------------------------------------

// Keep Matter pairing/fabric data next to the rest of the app's data so it
// survives restarts (re-pairing is only needed if this folder is deleted).
const storageDir = join(configDir, "matter-storage");
mkdirSync(storageDir, { recursive: true });
const environment = Environment.default;
environment.vars.set("storage.path", storageDir);

const server = await ServerNode.create({
    id: "wemo-matter-bridge",
    network: { port: 5540 },
    productDescription: {
        name: "Wemo Bridge",
        deviceType: AggregatorEndpoint.deviceType,
    },
    basicInformation: {
        vendorName: "WemoDuskDawn",
        vendorId: VendorId(0xfff1),
        productName: "Wemo Bridge",
        productLabel: "Wemo Bridge",
        productId: 0x8001,
        serialNumber: "wemo-bridge-1",
        uniqueId: "wemo-bridge-1",
    },
});

const aggregator = new Endpoint(AggregatorEndpoint, { id: "aggregator" });
await server.add(aggregator);

// One Matter plug endpoint per Wemo. The endpoint id is derived from the
// switch's IP so Google Home keeps device identity across restarts -
// another reason to give the switches DHCP reservations.
const plugs = [];
for (const dev of devices) {
    const id = "wemo-" + dev.ip.replaceAll(".", "-");
    const label = String(dev.name ?? dev.ip).substring(0, 32);
    const endpoint = new Endpoint(OnOffPlugInUnitDevice.with(BridgedDeviceBasicInformationServer), {
        id,
        bridgedDeviceBasicInformation: {
            nodeLabel: label,
            productName: label,
            productLabel: label,
            serialNumber: id,
            reachable: true,
        },
    });
    await aggregator.add(endpoint);

    // Suppresses the SOAP write-back when WE update Matter state from a poll.
    let applyingPoll = false;

    endpoint.events.onOff.onOff$Changed.on(async value => {
        if (applyingPoll) return;
        const ok = await setBinaryState(dev, value ? 1 : 0);
        console.log(`[google] ${label} -> ${value ? "ON" : "OFF"}: ${ok ? "ok" : "FAILED (switch unreachable)"}`);
    });

    plugs.push({
        dev,
        label,
        endpoint,
        async poll() {
            const state = await getBinaryState(dev);
            const reachable = state !== null;
            try {
                if (reachable && endpoint.state.onOff.onOff !== (state === 1)) {
                    applyingPoll = true;
                    await endpoint.set({ onOff: { onOff: state === 1 } });
                    applyingPoll = false;
                }
                if (endpoint.state.bridgedDeviceBasicInformation.reachable !== reachable) {
                    await endpoint.set({ bridgedDeviceBasicInformation: { reachable } });
                }
            } catch (e) {
                applyingPoll = false;
                console.log(`[poll] ${label}: ${e.message}`);
            }
        },
    });
}

// Keep Google Home tiles in sync with reality (manual button presses on the
// switch, the dusk/dawn scheduler, the control GUI...).
async function pollAll() {
    for (const plug of plugs) await plug.poll();
}
await pollAll();
setInterval(pollAll, POLL_SECONDS * 1000);

await server.start();

console.log("");
console.log(`Wemo Matter bridge running with ${plugs.length} switch(es): ${plugs.map(p => p.label).join(", ")}`);

if (!server.lifecycle.isCommissioned) {
    const { qrPairingCode, manualPairingCode } = server.state.commissioning.pairingCodes;
    console.log("");
    console.log("NOT PAIRED YET - in the Google Home app choose  + > Add device > Matter device");
    console.log("and scan this QR code (or type the manual code):");
    console.log("");
    console.log(QrCode.get(qrPairingCode));
    console.log(`Manual pairing code: ${manualPairingCode}`);
    console.log(`QR code as image: https://project-chip.github.io/connectedhomeip/qrcode.html?data=${encodeURIComponent(qrPairingCode)}`);
} else {
    console.log("Already paired with a Matter controller (Google Home). Nothing else to do.");
}
console.log("");
console.log("Leave this running. Press Ctrl+C to stop.");
