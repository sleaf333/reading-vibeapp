export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(200).send('Proxy is running.');
  }
  const upstream = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': req.headers['x-api-key'] || '',
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify(req.body),
  });
  const data = await upstream.json();
  res.status(upstream.status).json(data);
}
