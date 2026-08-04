// Social-preview image for /post/<id>. Serves the post's own first image when
// it has one, and the branded default card otherwise, so a shared link never
// previews without an image.
//
// Post media arrives in one of three shapes:
//   data:image/...;base64,...      inline (older posts, avatars)
//   /media/posts/<uuid>.jpg        served from our origin via netlify.toml
//   https://media.giphy.com/...    absolute, third-party

const API = 'http://63.181.201.175';
const DEFAULT_CARD = '/brand/og-default.png';

function decodeDataUrl(dataUrl) {
  const mimeType = dataUrl.slice(5, dataUrl.indexOf(';'));
  const binaryStr = atob(dataUrl.slice(dataUrl.indexOf(',') + 1));
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) bytes[i] = binaryStr.charCodeAt(i);
  return { bytes, mimeType };
}

function image(body, contentType) {
  return new Response(body, {
    headers: {
      'Content-Type': contentType,
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

async function defaultCard(origin) {
  const res = await fetch(`${origin}${DEFAULT_CARD}`);
  if (!res.ok) return new Response('No image', { status: 404 });
  return image(res.body, 'image/png');
}

export default async (request, context) => {
  const url = new URL(request.url);
  const match = url.pathname.match(/^\/post\/(\d+)\/og-image$/);
  if (!match) return context.next();

  let post;
  try {
    const res = await fetch(`${API}/api/posts/${match[1]}/`);
    if (!res.ok) return defaultCard(url.origin);
    post = await res.json();
  } catch {
    return defaultCard(url.origin);
  }

  // Prefer the post's first image; then, for a post that is just a pasted
  // link, that link's own thumbnail — a shared TikTok should preview as the
  // video, not as a branded placeholder. The author's avatar is the next
  // fallback, and the branded card the last.
  const media = post.media || [];
  const linkThumb = (post.link_preview && post.link_preview.image_url) || '';
  const source =
    media.find((m) => m.type === 'image')?.url || linkThumb || post.avatarUrl || '';

  if (source.startsWith('data:')) {
    const { bytes, mimeType } = decodeDataUrl(source);
    return image(bytes, mimeType);
  }

  if (source.startsWith('/') || source.startsWith('http')) {
    const absolute = source.startsWith('/') ? `${url.origin}${source}` : source;
    try {
      const res = await fetch(absolute);
      const type = res.headers.get('content-type') || '';
      if (res.ok && type.startsWith('image/')) return image(res.body, type);
    } catch {
      // fall through to the branded card
    }
  }

  return defaultCard(url.origin);
};
