import 'package:omni_ai/omni_ai.dart';

import '../core/settings.dart';
import '../models/book.dart';
import '../models/doc.dart';
import 'usage_log.dart';

/// Reading-assistant prompts on top of omni_ai (Vercel AI Gateway + Google).
class Ai {
  Ai._();

  static final OmniAI omni = OmniAI(appName: 'Alexandria', defaultProvider: 'google');

  static const providers = ['google', 'gateway'];

  static const presetModels = <(String, String)>[
    ('google:gemini-2.5-flash', 'Gemini 2.5 Flash'),
    ('google:gemini-2.5-pro', 'Gemini 2.5 Pro'),
    ('gateway:google/gemini-2.5-flash', 'Gateway · Gemini Flash'),
    ('gateway:openai/gpt-5-mini', 'Gateway · GPT-5 mini'),
    ('gateway:anthropic/claude-sonnet-4.5', 'Gateway · Claude Sonnet'),
    ('gateway:xai/grok-4-fast', 'Gateway · Grok 4 Fast'),
  ];

  static Future<void> get ready => omni.ready;

  static bool get configured => omni.google.isConfigured || omni.gateway.isConfigured;

  /// The chosen model, falling back to whichever provider has a key.
  static String get model {
    final m = Settings.i.aiModel;
    final provider = m.split(':').first;
    if (provider == 'google' && omni.google.isConfigured) return m;
    if (provider == 'gateway' && omni.gateway.isConfigured) return m;
    if (omni.google.isConfigured) return 'google:gemini-2.5-flash';
    if (omni.gateway.isConfigured) return 'gateway:google/gemini-2.5-flash';
    return m;
  }

  static String get _style {
    final s = Settings.i;
    final level = switch (s.aiLevel) {
      'simple' => 'Explain as if to a curious 12-year-old. Short sentences, no jargon.',
      'expert' => 'Be precise and scholarly. Assume an expert reader; cite context, etymology, and references where useful.',
      _ => 'Be clear and concise, like a great teacher in the margin of a book.',
    };
    return '$level Answer in ${s.aiLanguage}. Use short paragraphs and plain Markdown (bold, bullet lists) only when it helps.';
  }

  static String _bookLine(Book b) => '"${b.title}"${b.author.isNotEmpty ? ' by ${b.author}' : ''}';

  static String _spoiler(Book b) => Settings.i.aiSpoilerGuard
      ? ' The reader is ${(b.progress * 100).round()}% through the book. Never reveal plot events beyond that point unless explicitly asked.'
      : '';

  static Stream<String> explain({required Book book, required String selection, required String context, String mode = 'explain'}) {
    final task = switch (mode) {
      'simplify' => 'Rewrite the selected passage in simpler, modern language, keeping its meaning.',
      'translate' => 'Translate the selected passage into ${Settings.i.aiLanguage == 'English' ? 'Spanish' : Settings.i.aiLanguage}, then add one line on any nuance lost in translation.',
      'context' => 'Explain who or what the selection refers to within this book, and why it matters here.',
      'define' => 'Define the selected word or phrase as it is used in this sentence. Give pronunciation, part of speech, the in-context meaning, and one example.',
      _ => 'Explain the selected passage: what it means, any references, idioms or difficult words, and why it matters.',
    };
    return _counted(omni
        .streamText(
          model: model,
          system: 'You are a reading companion inside an ebook reader. The reader is reading ${_bookLine(book)}.${_spoiler(book)} $_style',
          prompt: '$task\n\nSELECTION:\n"""$selection"""\n\nSURROUNDING TEXT:\n"""$context"""',
        ));
  }

  /// What is this book? Works even before reading, from metadata + opening pages.
  static Stream<String> aboutBook(Book book, {ParsedDoc? doc}) {
    final opening = doc == null ? '' : _excerpt(doc, 0, 3000);
    return _counted(omni
        .streamText(
          model: model,
          system: 'You are a well-read librarian. $_style',
          prompt: 'Tell me about the book ${_bookLine(book)}. '
              'Cover: what it is (genre, era, why it is known), what it is about without spoilers, its themes, who would enjoy it, and how long/hard a read it is. '
              'End with three similar books.\n\n'
              '${book.description.isNotEmpty ? 'Catalogue description: ${book.description}\n\n' : ''}'
              '${opening.isNotEmpty ? 'Opening text:\n"""$opening"""' : ''}',
        ));
  }

  static Stream<String> recap(Book book, ParsedDoc doc, int block) {
    final start = (block - 220).clamp(0, doc.blocks.length);
    return _counted(omni
        .streamText(
          model: model,
          system: 'You are a reading companion. ${_spoiler(book)} $_style',
          prompt: 'I am returning to ${_bookLine(book)}. Give me a short "previously on" recap of what I just read, '
              'then list the key people/ideas to keep in mind. Use only this text:\n"""${_excerpt(doc, start, 9000)}"""',
        ));
  }

  /// Free-form chat about the book.
  static Stream<String> chat(Book book, List<Message> history, {String? passage}) {
    return _counted(omni
        .streamText(
          model: model,
          system: 'You are a reading companion for ${_bookLine(book)}.${_spoiler(book)} $_style'
              '${passage == null ? '' : '\nThe reader is currently looking at:\n"""$passage"""'}',
          messages: history,
        ));
  }

  /// The growing answer, with the call's tokens and cost logged once it ends.
  static Stream<String> _counted(StreamTextResult call) {
    final used = model;
    call.usage.then((u) {
      UsageLog.i.addText(used, u, listPrice: omni.estimateCost(used, u));
    }, onError: (_) {}); // a failed call has nothing to log; the stream reports the error
    return call.accumulatedText;
  }

  static String _excerpt(ParsedDoc doc, int from, int maxChars) {
    final buf = StringBuffer();
    for (var i = from; i < doc.blocks.length && buf.length < maxChars; i++) {
      if (doc.blocks[i].text.isNotEmpty) buf.writeln(doc.blocks[i].text);
    }
    final s = buf.toString();
    return s.length > maxChars ? s.substring(0, maxChars) : s;
  }
}
