// League weeks run Monday 00:00 to Monday 00:00 Turkish time (UTC+3, no DST),
// the same as the app's local league in lib/data/league.dart.
const TR_OFFSET_MS = 3 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function trDate(now: Date): Date {
  return new Date(now.getTime() + TR_OFFSET_MS);
}

/** "yyyy-mm-dd" of the Turkish calendar day containing [now]. */
export function dayKey(now: Date): string {
  const d = trDate(now);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/** dayKey of the Monday that starts the league week containing [now]. */
export function weekKey(now: Date): string {
  const d = trDate(now);
  const sinceMonday = (d.getUTCDay() + 6) % 7;
  return dayKey(new Date(now.getTime() - sinceMonday * DAY_MS));
}

/** weekKey of the week before the one containing [now]. */
export function previousWeekKey(now: Date): string {
  return weekKey(new Date(now.getTime() - 7 * DAY_MS));
}
