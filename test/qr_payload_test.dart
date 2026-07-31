import 'package:copy_once/utils/qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('links', () {
    test('encodes an https URL as itself so any scanner opens it', () {
      final payload = QrPayload.forContent('https://example.com/page?a=1');

      expect(payload.action, QrAction.openLink);
      expect(payload.data, 'https://example.com/page?a=1');
    });

    test('does not treat a non-http scheme as a link', () {
      // A captured javascript: or file: string must never be presented as
      // something safe to open.
      final payload = QrPayload.forContent('javascript:alert(1)');

      expect(payload.action, QrAction.copyText);
    });
  });

  group('email', () {
    test('encodes as mailto so the scanner offers to write', () {
      final payload = QrPayload.forContent('someone@example.com');

      expect(payload.action, QrAction.email);
      expect(payload.data, 'mailto:someone@example.com');
    });

    test('a sentence containing an address is just text', () {
      final payload = QrPayload.forContent('email me at a@b.com please');

      expect(payload.action, QrAction.copyText);
    });
  });

  group('phone', () {
    test('encodes as tel and strips punctuation', () {
      final payload = QrPayload.forContent('(555) 123-4567');

      expect(payload.action, QrAction.call);
      expect(payload.data, 'tel:5551234567');
    });

    test('keeps a leading plus so international numbers dial correctly', () {
      final payload = QrPayload.forContent('+961 3 123 456');

      expect(payload.action, QrAction.call);
      expect(payload.data, 'tel:+9613123456');
    });

    test('a short number is text, not a phone number', () {
      // An order number or year must not become a dial prompt.
      expect(QrPayload.forContent('12345').action, QrAction.copyText);
      expect(QrPayload.forContent('2026').action, QrAction.copyText);
    });

    test('a very long digit run is text, not a phone number', () {
      expect(
        QrPayload.forContent('1234567890123456789').action,
        QrAction.copyText,
      );
    });

    test('digits mixed with letters are text', () {
      expect(QrPayload.forContent('ORDER-4455667').action, QrAction.copyText);
    });
  });

  group('plain text', () {
    test('is encoded verbatim', () {
      final payload = QrPayload.forContent('the meeting is at four');

      expect(payload.action, QrAction.copyText);
      expect(payload.data, 'the meeting is at four');
      expect(payload.isTruncated, isFalse);
    });

    test('trims surrounding whitespace', () {
      expect(QrPayload.forContent('  hello  ').data, 'hello');
    });
  });

  group('capacity', () {
    test('long content is cut to a scannable length and says so', () {
      final long = 'a' * (QrPayload.maxLength + 500);

      final payload = QrPayload.forContent(long);

      expect(payload.isTruncated, isTrue);
      expect(payload.data.length, QrPayload.maxLength);
    });

    test('content at exactly the limit is not truncated', () {
      final exact = 'a' * QrPayload.maxLength;

      expect(QrPayload.forContent(exact).isTruncated, isFalse);
    });
  });

  group('scanner promise', () {
    test('every action explains what the other person will get', () {
      for (final action in QrAction.values) {
        expect(action.scannerPromise, isNotEmpty);
        expect(action.title, isNotEmpty);
      }
    });
  });
}
