export async function onRequestPost({ request }) {
  const body = await request.text();
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': request.headers.get('x-api-key') || '',
      'anthropic-version': '2023-06-01',
    },
    body,
  });
  return new Response(await res.text(), {
    status: res.status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function onRequestOptions() {
  return new Response(null, { status: 204 });
}

export async function onRequestGet() {
  return new Response('Proxy is running.', { status: 200 });
}
