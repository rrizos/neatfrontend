import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/core/link_preview.dart';

void main() {
  group('extractUrls', () {
    test('finds a plain https link', () {
      expect(extractUrls('δες εδώ https://www.in.gr/news/ φοβερό'),
          ['https://www.in.gr/news/']);
    });

    test('finds a bare www host', () {
      expect(extractUrls('www.in.gr έχει το άρθρο'), ['www.in.gr']);
    });

    test('finds a bare host.tld with a path', () {
      expect(extractUrls('μπες neatapp.gr/post/12 τώρα'), ['neatapp.gr/post/12']);
    });

    test('finds several links in order', () {
      expect(
        extractUrls('https://a.com και μετά https://b.gr/x'),
        ['https://a.com', 'https://b.gr/x'],
      );
    });

    test('ignores plain text with no links', () {
      expect(extractUrls('καλημέρα σε όλους, τι κάνετε;'), isEmpty);
    });
  });

  group('trailing punctuation', () {
    test('a full stop after a link is not part of it', () {
      expect(extractUrls('δες https://in.gr/news.'), ['https://in.gr/news']);
    });

    test('a comma after a link is not part of it', () {
      expect(extractUrls('https://in.gr, και άλλα'), ['https://in.gr']);
    });

    test('a link in parentheses keeps its own balanced paren', () {
      expect(
        extractUrls('https://en.wikipedia.org/wiki/Athens_(Greece)'),
        ['https://en.wikipedia.org/wiki/Athens_(Greece)'],
      );
    });

    test('an unbalanced closing paren is dropped', () {
      expect(extractUrls('(δες https://in.gr/news)'), ['https://in.gr/news']);
    });

    test('Greek quotes and ellipsis are trimmed', () {
      expect(extractUrls('«https://in.gr»…'), ['https://in.gr']);
    });
  });

  group('firstUrl', () {
    test('returns only the first link, like Instagram', () {
      expect(firstUrl('https://a.com then https://b.com'), 'https://a.com');
    });

    test('returns null when there is nothing to preview', () {
      expect(firstUrl('just talking'), isNull);
    });
  });

  group('normaliseUrl', () {
    test('leaves an explicit scheme alone', () {
      expect(normaliseUrl('http://in.gr'), 'http://in.gr');
      expect(normaliseUrl('https://in.gr'), 'https://in.gr');
    });

    test('adds https to a bare host', () {
      expect(normaliseUrl('www.in.gr'), 'https://www.in.gr');
      expect(normaliseUrl('neatapp.gr/post/1'), 'https://neatapp.gr/post/1');
    });
  });

  group('LinkPreviewData', () {
    LinkPreviewData parse(Map<String, dynamic> json) =>
        LinkPreviewData.fromJson(json);

    test('a TikTok reads as a video by a named creator', () {
      final d = parse({
        'url': 'https://www.tiktok.com/@zachking/video/1',
        'title': 'caption', 'site_name': 'TikTok', 'kind': 'video',
        'author_name': 'Zach King', 'author_handle': 'zachking',
        'image_url': 'https://cdn/t.jpg',
        'image_width': 576, 'image_height': 1090,
      });
      expect(d.isVideo, isTrue);
      expect(d.hasAuthor, isTrue);
      expect(d.authorLabel, '@zachking');
      expect(d.displayHost, 'TikTok');
      expect(d.imageAspect, closeTo(0.528, 0.01));
    });

    test('a plain news site has no author and is not a video', () {
      final d = parse({
        'url': 'https://www.in.gr/', 'title': 'in.gr',
        'site_name': 'in.gr', 'kind': 'website',
      });
      expect(d.isVideo, isFalse);
      expect(d.hasAuthor, isFalse);
      expect(d.authorLabel, '');
    });

    test('falls back to the display name when there is no handle', () {
      final d = parse({'author_name': 'Rick Astley', 'author_handle': ''});
      expect(d.authorLabel, 'Rick Astley');
    });

    test('missing dimensions leave the aspect for the card to measure', () {
      final d = parse({'image_url': 'https://cdn/x.jpg'});
      expect(d.imageAspect, isNull);
    });

    test('string dimensions from JSON are tolerated', () {
      final d = parse({'image_width': '576', 'image_height': '1090'});
      expect(d.imageAspect, closeTo(0.528, 0.01));
    });

    test('displayHost strips www when the server sent no site name', () {
      final d = parse({'resolved_url': 'https://www.example.com/a'});
      expect(d.displayHost, 'example.com');
    });
  });

  group('false positives', () {
    test('an email address is not treated as a link', () {
      expect(extractUrls('γράψε στο someone@example.com'), isEmpty);
    });

    test('a decimal number is not a link', () {
      expect(extractUrls('κάνει 12.50 ευρώ'), isEmpty);
    });

    test('a sentence with no space after the full stop is not a link', () {
      expect(extractUrls('τέλος.Ξεκινάμε πάλι'), isEmpty);
    });
  });
}
