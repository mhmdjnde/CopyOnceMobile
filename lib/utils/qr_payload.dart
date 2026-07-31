import '../models/clipboard_item.dart';

/// What a scanner will be able to do with a QR code.
///
/// QR encodes intent, not just characters: a `tel:` payload makes a phone offer
/// to dial, `mailto:` to compose. Choosing the right form turns a clipboard item
/// into the action someone actually wants, instead of a wall of text they have
/// to copy by hand.
enum QrAction {
  /// An `https://` link. Every scanner opens these.
  openLink,

  /// A `tel:` number.
  call,

  /// A `mailto:` address.
  email,

  /// Plain text. Scanners display it; most Android ones offer a copy button.
  copyText,
}

extension QrActionCopy on QrAction {
  /// What the person scanning will be offered, in their terms.
  String get scannerPromise => switch (this) {
    QrAction.openLink => 'Opens the link in their browser',
    QrAction.call => 'Offers to call the number',
    QrAction.email => 'Offers to write an email',
    QrAction.copyText => 'Shows the text so they can copy it',
  };

  String get title => switch (this) {
    QrAction.openLink => 'Scan to open',
    QrAction.call => 'Scan to call',
    QrAction.email => 'Scan to email',
    QrAction.copyText => 'Scan to copy',
  };
}

/// A clipboard item turned into something scannable.
class QrPayload {
  const QrPayload({
    required this.data,
    required this.action,
    this.isTruncated = false,
  });

  /// Exactly what gets encoded.
  final String data;

  final QrAction action;

  /// True when the content was too long for a reliable QR and was cut short.
  final bool isTruncated;

  /// Practical ceiling for one QR.
  ///
  /// The format allows more, but past roughly this much the code becomes dense
  /// enough that phone cameras struggle — a QR nobody can scan is worse than an
  /// honest "too long".
  static const int maxLength = 1000;

  /// Matches a phone number: an optional `+` or area-code bracket, then the
  /// digits, spaces, dashes, dots and parentheses people actually paste.
  ///
  /// Shape only — the digit count is checked separately, so a copied order
  /// number or year does not turn into a dial prompt.
  static final RegExp _phonePattern = RegExp(r'^\+?[\d(][\d\s().-]{5,20}$');

  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$',
  );

  /// Decides the most useful encoding for [item].
  static QrPayload forItem(ClipboardItem item) => forContent(item.content);

  static QrPayload forContent(String content) {
    final trimmed = content.trim();

    if (ClipboardItem.looksLikeLink(trimmed)) {
      return _build(trimmed, QrAction.openLink);
    }
    if (_isEmail(trimmed)) {
      return _build('mailto:$trimmed', QrAction.email);
    }
    final phone = _asPhoneNumber(trimmed);
    if (phone != null) {
      return _build('tel:$phone', QrAction.call);
    }
    return _build(trimmed, QrAction.copyText);
  }

  static QrPayload _build(String data, QrAction action) {
    if (data.length <= maxLength) {
      return QrPayload(data: data, action: action);
    }
    return QrPayload(
      data: data.substring(0, maxLength),
      action: action,
      isTruncated: true,
    );
  }

  static bool _isEmail(String value) =>
      !value.contains(RegExp(r'\s')) && _emailPattern.hasMatch(value);

  /// The dialable form of [value], or null when it is not a phone number.
  ///
  /// Punctuation is stripped because `tel:` wants digits, but a leading `+` is
  /// kept — without it an international number dials wrongly.
  static String? _asPhoneNumber(String value) {
    if (!_phonePattern.hasMatch(value)) return null;

    final hasPlus = value.startsWith('+');
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;

    return hasPlus ? '+$digits' : digits;
  }
}
