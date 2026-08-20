String awaitExecutionReplacement(String expression) {
  return 'await ($expression).exit';
}

String returnExecutionReplacement(String expression) {
  return 'return ($expression).exit;';
}

String ownCommandReplacement(String expression) {
  return 'ownCommand($expression)';
}

String runtimeTryFinallyReplacement({
  required String statements,
  required String indentation,
  required String oneIndent,
  required String runtimeName,
}) {
  final nestedIndent = '$indentation$oneIndent';
  final indentedStatements = statements.replaceAll(
    '\n$indentation',
    '\n$nestedIndent',
  );

  return 'try {\n'
      '$nestedIndent$indentedStatements\n'
      '$indentation} finally {\n'
      '${nestedIndent}await $runtimeName.close();\n'
      '$indentation}';
}
