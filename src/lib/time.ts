export function isoTimeAgo(milliseconds: number) {
  return new Date(Date.now() - milliseconds).toISOString();
}

export function isWithinRecentWindow(value: string | null | undefined, milliseconds: number) {
  if (!value) return false;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) && Date.now() - timestamp < milliseconds;
}
