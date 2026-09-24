mixin CommonLogStorageOperations {
  String logFileNameOfDate(DateTime date) {
    final String monthWithPadding = date.month.toString().padLeft(2, '0');
    final String dayWithPadding = date.day.toString().padLeft(2, '0');
    return "APP-LOGS_${date.year}-$monthWithPadding-$dayWithPadding.log";
  }

  static DateTime parseLogFileDate(String fileName) {
    if (!isLogFileNameValid(fileName)) {
      throw Exception("Invalid file name: $fileName");
    }

    // Read the date from the end: a valid prefix may itself contain dots.
    final date = RegExp(
      r'(\d{4})-(\d{1,2})-(\d{1,2})\.(log|txt)$',
    ).firstMatch(fileName)!;

    return DateTime(
      int.parse(date[1]!),
      int.parse(date[2]!),
      int.parse(date[3]!),
    );
  }

  /// Orders valid log file names by their dates, oldest first.
  ///
  /// A name may carry any prefix, so lexical order is not chronological.
  static int compareLogFileNames(String a, String b) {
    final byDate = parseLogFileDate(a).compareTo(parseLogFileDate(b));
    return byDate != 0 ? byDate : a.compareTo(b);
  }

  static DateTime? tryParseLogFileDate(String fileName) {
    try {
      if (!isLogFileNameValid(fileName)) {
        return null;
      }

      return parseLogFileDate(fileName);
    } catch (e) {
      return null;
    }
  }

  static bool isLogFileNameValid(String fileName) {
    // Verify that file name is in the correct format.
    // The prefix is optional and the file extension must be the end of the
    // string. Bear in mind that `mm` and `dd` can be one or two digits.
    // E.g. {prefix:string}_yyyy-mm-dd.{log or txt}
    final pattern = r'^(.*_)?\d{4}-\d{1,2}-\d{1,2}\.(log|txt)$';

    // Use RegExp to create a regular expression from the pattern
    final regExp = RegExp(pattern);

    // Test the fileName against the regular expression
    return regExp.hasMatch(fileName);
  }
}
