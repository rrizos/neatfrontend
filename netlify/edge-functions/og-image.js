export default async (request, context) => {
  const url = new URL(request.url);
  const match = url.pathname.match(/^\/post\/(\d+)\/og-image$/);
  if (!match) return context.next();

  const postId = match[1];

  let post;
  try {
    const res = await fetch(`http://63.181.201.175/api/posts/${postId}/`);
    if (!res.ok) return new Response('Not found', { status: 404 });
    post = await res.json();
  } catch {
    return new Response('Error', { status: 500 });
  }

  const media = post.media || [];
  const imageItem = media.find((m) => m.type === 'image');
  const dataUrl = imageItem?.url || post.imageUrl || post.avatarUrl || '';

  if (!dataUrl.startsWith('data:')) {
    return new Response('No image', { status: 404 });
  }

  const mimeType = dataUrl.slice(5, dataUrl.indexOf(';'));
  const base64 = dataUrl.slice(dataUrl.indexOf(',') + 1);

  const binaryStr = atob(base64);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i);
  }

  return new Response(bytes, {
    headers: {
      'Content-Type': mimeType,
      'Cache-Control': 'public, max-age=3600',
    },
  });
};
