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

    final date = fileName.split(".").first.split("_").last;

    final dateParts = date.split("-");

    final year = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final day = int.parse(dateParts[2]);

    return DateTime(year, month, day);
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
