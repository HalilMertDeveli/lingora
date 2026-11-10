/// Saves [content] as a file. Only the web build can do this; elsewhere it
/// returns false so the caller can show the text instead.
bool downloadText(String filename, String content, {String mime = 'text/csv'}) => false;
