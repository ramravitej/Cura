/// ChatML prompt formatting (mirrors native template).
library;

const String _imStart = '<|im_start|>';
const String _imEnd = '<|im_end|>';

/// System block.
String chatmlSystemBlock(String system) => '$_imStart' 'system\n$system$_imEnd\n';

/// Incremental user turn. `closePrev` closes a previous open assistant turn.
String chatmlUserTurn(String content, {required bool closePrev}) =>
    '${closePrev ? '$_imEnd\n' : ''}$_imStart'
    'user\n$content$_imEnd\n$_imStart'
    'assistant\n';

/// Full conversation format builder.
String chatmlFull(List<({String role, String text})> turns) {
  final b = StringBuffer();
  for (final t in turns) {
    b.write('$_imStart${t.role}\n${t.text}$_imEnd\n');
  }
  b.write('$_imStart' 'assistant\n');
  return b.toString();
}

/// Formats conversation turns according to the model's template (`chatml`, `smolvlm`, `gemma4`).
String formatPromptForTemplate(
  String template,
  List<({String role, String text})> turns,
) {
  final key = template.toLowerCase();
  if (key == 'smolvlm' || key == 'smolvlm2') {
    final b = StringBuffer(_imStart);
    for (final t in turns) {
      if (t.role == 'system') {
        b.write('${t.text.trim()}\n\n');
      } else if (t.role == 'user') {
        b.write('User: ${t.text.trim()}<end_of_utterance>\n');
      } else {
        b.write('Assistant: ${t.text.trim()}<end_of_utterance>\n');
      }
    }
    b.write('Assistant:');
    return b.toString();
  }
  if (key == 'gemma4' || key == 'gemma-4') {
    final b = StringBuffer('<bos>');
    for (final t in turns) {
      final role = t.role == 'assistant' ? 'model' : t.role;
      b.write('<|turn>$role\n${t.text.trim()}<turn|>\n');
    }
    b.write('<|turn>model\n');
    return b.toString();
  }
  return chatmlFull(turns);
}
