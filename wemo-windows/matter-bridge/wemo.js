// wemo.js - minimal local Wemo control over UPnP/SOAP (same protocol the
// PowerShell app uses). No cloud, no dependencies.

import http from "node:http";

const WEMO_PORTS = [49153, 49152, 49154, 49155];

function soapRequest(ip, port, action, innerXml) {
    const body =
        `<?xml version="1.0" encoding="utf-8"?>` +
        `<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">` +
        `<s:Body>${innerXml}</s:Body></s:Envelope>`;
    return new Promise((resolve, reject) => {
        const req = http.request(
            {
                host: ip,
                port,
                path: "/upnp/control/basicevent1",
                method: "POST",
                timeout: 5000,
                headers: {
                    "Content-Type": 'text/xml; charset="utf-8"',
                    SOAPACTION: `"urn:Belkin:service:basicevent:1#${action}"`,
                    "Content-Length": Buffer.byteLength(body),
                },
            },
            res => {
                let data = "";
                res.on("data", chunk => (data += chunk));
                res.on("end", () => resolve(data));
            },
        );
        req.on("timeout", () => req.destroy(new Error("timeout")));
        req.on("error", reject);
        req.end(body);
    });
}

function portsFor(device) {
    const preferred = Number(device.port) || 49153;
    return [preferred, ...WEMO_PORTS.filter(p => p !== preferred)];
}

// Resolves 0 (off), 1 (on), or null (unreachable). Remembers a working port.
export async function getBinaryState(device) {
    for (const port of portsFor(device)) {
        try {
            const xml = await soapRequest(device.ip, port, "GetBinaryState",
                '<u:GetBinaryState xmlns:u="urn:Belkin:service:basicevent:1"></u:GetBinaryState>');
            const m = xml.match(/<BinaryState>(\d+)/);
            if (m) {
                device.port = port;
                // Insight switches report 8 for "on, standby" - nonzero means on.
                return Number(m[1]) === 0 ? 0 : 1;
            }
        } catch {
            // try next port
        }
    }
    return null;
}

// Resolves true on success. Wemos answer "Error" when asked to switch to the
// state they are already in - that counts as success.
export async function setBinaryState(device, state) {
    for (const port of portsFor(device)) {
        try {
            const xml = await soapRequest(device.ip, port, "SetBinaryState",
                `<u:SetBinaryState xmlns:u="urn:Belkin:service:basicevent:1"><BinaryState>${state}</BinaryState></u:SetBinaryState>`);
            device.port = port;
            if (/<BinaryState>Error/.test(xml)) {
                return (await getBinaryState(device)) === state;
            }
            return true;
        } catch {
            // try next port
        }
    }
    return false;
}
