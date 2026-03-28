export function createLogger(fn: string) {
  function toEntry(level: string, args: unknown[]): string {
    const msg = typeof args[0] === 'string' ? args[0] : ''
    const rest = typeof args[0] === 'string' ? args.slice(1) : args
    const entry: Record<string, unknown> = { level, fn, msg, ts: Date.now() }
    if (rest.length === 1) {
      const val = rest[0]
      entry.detail = val instanceof Error ? val.message : val
    } else if (rest.length > 1) {
      entry.detail = rest.map(v => v instanceof Error ? v.message : v)
    }
    return JSON.stringify(entry)
  }

  return {
    error(...args: unknown[]) { console.error(toEntry('error', args)) },
    warn(...args: unknown[]) { console.warn(toEntry('warn', args)) },
    info(...args: unknown[]) { console.log(toEntry('info', args)) },
  }
}
