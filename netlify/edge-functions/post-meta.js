const esc = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

export default async (request, context) => {
  const url = new URL(request.url);
  const match = url.pathname.match(/^\/post\/(\d+)$/);
  if (!match) return context.next();

  const postId = match[1];

  let post;
  try {
    const res = await fetch(`http://63.181.201.175/api/posts/${postId}/`);
    if (!res.ok) return context.next();
    post = await res.json();
  } catch {
    return context.next();
  }

  const title = `@${post.author} on Neat${post.city ? ` · ${post.city}` : ''}`;
  const raw = post.text || '';
  const description = raw.length > 160 ? raw.slice(0, 157) + '…' : raw || 'Check out this post on Neat';
  const ogImage = `${url.origin}/post/${postId}/og-image`;

  const tags = `
  <meta property="og:type" content="article" />
  <meta property="og:site_name" content="Neat" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:image" content="${ogImage}" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:url" content="${esc(url.toString())}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  <meta name="twitter:image" content="${ogImage}" />`;

  const indexRes = await context.next();
  const html = await indexRes.text();
  const injected = html.replace('</head>', `${tags}\n</head>`);

  return new Response(injected, {
    status: indexRes.status,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });
};
