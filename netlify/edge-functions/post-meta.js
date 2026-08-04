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

  const raw = (post.text || '').trim();
  // A post that is just a pasted link previewed as its own URL, which told a
  // recipient nothing. The API resolves the link for us, so show what it
  // actually points at — "Zach King · TikTok" rather than the tiktok.com URL.
  const link = post.link_preview || null;
  const by = link ? (link.author_name || link.author_handle || '').trim() : '';
  const site = link ? (link.site_name || '').trim() : '';

  // Preference order for a link post: the link's own caption, then whose post
  // it is ("andre0268 on TikTok") when the caption is empty, and only then the
  // post text — which for these posts is the bare URL and says nothing.
  const linkTitle = link ? (link.title || '').trim() : '';
  const byline = by && site ? `${by} on ${site}` : by || site;
  const fallback = raw.length > 100 ? raw.slice(0, 97) + '…' : raw || `Post by @${post.author}`;
  const title = linkTitle || byline || fallback;

  let description = `@${post.author} on Neat${post.city ? ' · ' + post.city : ''}`;
  if (link) {
    // Credit whoever made the thing being linked, next to whoever shared it.
    const source = by && site ? `${by} · ${site}` : by || site;
    if (source) description = `${source} — shared by @${post.author}`;
  }

  const ogImage = `${url.origin}/post/${postId}/og-image`;

  // No og:image:width/height — the endpoint serves the post's own photo when
  // it has one, so the dimensions vary; crawlers read them off the image.
  const tags = `
  <meta property="og:type" content="article" />
  <meta property="og:site_name" content="Neat" />
  <meta property="og:locale" content="el_GR" />
  <meta property="og:title" content="${esc(title)}" />
  <meta property="og:description" content="${esc(description)}" />
  <meta property="og:image" content="${ogImage}" />
  <meta property="og:url" content="${esc(url.toString())}" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="${esc(title)}" />
  <meta name="twitter:description" content="${esc(description)}" />
  <meta name="twitter:image" content="${ogImage}" />
  <meta name="description" content="${esc(description)}" />
  <title>${esc(title)}</title>`;

  // Ask for the Flutter shell by name rather than relying on context.next()
  // picking up the SPA rewrite — `/` is the landing page now, so the shell has
  // to be addressed explicitly.
  const shellRes = await fetch(`${url.origin}/app.html`);
  if (!shellRes.ok) return context.next();

  // Drop the shell's own generic <title>/<meta description> so the post's win.
  const html = (await shellRes.text())
    .replace(/\n?\s*<title>[^<]*<\/title>/, '')
    .replace(/\n?\s*<meta name="description"[^>]*>/, '');
  const injected = html.replace('</head>', `${tags}\n</head>`);

  return new Response(injected, {
    status: 200,
    headers: { 'content-type': 'text/html; charset=utf-8' },
  });
};
