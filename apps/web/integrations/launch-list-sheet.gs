/**
 * WattByte launch list: Google Apps Script receiver for LAUNCH_LIST_WEBHOOK_URL.
 * Setup is in apps/web/README.md ("Launch-list receiver"). Paste into Extensions → Apps Script
 * of the sign-up spreadsheet, set the script property KEY, deploy as a web app
 * (Execute as: Me, Who has access: Anyone) and use `<web app URL>?key=<KEY>` as the Worker secret.
 *
 * Apps Script cannot read request headers, so the key travels in the query string instead of
 * LAUNCH_LIST_WEBHOOK_TOKEN. Every answer is HTTP 200; a wrong key shows up only as a missing row.
 */
const COLUMNS = ['at', 'email', 'platform', 'source', 'utm_source', 'utm_medium', 'utm_campaign', 'utm_content'];

function doPost(e) {
  const key = PropertiesService.getScriptProperties().getProperty('KEY');
  if (!key || e.parameter.key !== key) return reply({ ok: false });

  let entry;
  try {
    entry = JSON.parse(e.postData.contents);
  } catch (err) {
    return reply({ ok: false });
  }

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheets()[0];
  if (sheet.getLastRow() === 0) sheet.appendRow(COLUMNS);
  sheet.appendRow(COLUMNS.map((column) => asText(entry[column])));
  return reply({ ok: true });
}

/** A cell value that Sheets keeps as text: a leading = + - or @ would otherwise start a formula. */
function asText(value) {
  const text = value == null ? '' : String(value);
  return /^[=+\-@]/.test(text) ? `'${text}` : text;
}

function reply(body) {
  return ContentService.createTextOutput(JSON.stringify(body)).setMimeType(ContentService.MimeType.JSON);
}
