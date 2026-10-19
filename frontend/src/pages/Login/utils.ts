export function canSubmitLogin(name: string, sessionReady: boolean, busy: boolean): boolean {
  return sessionReady && !busy && name.trim().length > 0;
}
