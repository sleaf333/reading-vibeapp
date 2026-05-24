// Cloudflare Worker — CORS proxy for Anthropic API
// Paste this into the Cloudflare Workers dashboard editor and click Deploy.
// Then paste the worker URL into the app's Parent Corner → Proxy URL field.

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  // Handle CORS preflight
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, x-api-key, anthropic-version',
        'Access-Control-Max-Age': '86400',
      },
    });
  }

  if (request.method !== 'POST') {
    return new Response('Proxy is running.', { status: 200 });
  }

  const body = await request.text();
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': request.headers.get('x-api-key') || '',
      'anthropic-version': request.headers.get('anthropic-version') || '2023-06-01',
    },
    body,
  });

  const text = await res.text();
  return new Response(text, {
    status: res.status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
