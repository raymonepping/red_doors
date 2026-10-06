// Same-origin calls to the BFF proxy (/api/v1/*). Errors carry the API's message.
export function api<T = any>(path: string, opts: { method?: 'GET' | 'POST', body?: unknown } = {}) {
  return $fetch<T>(`/api/v1${path}`, { method: opts.method ?? 'GET', body: opts.body as any })
}

export function errorText(err: any): string {
  return err?.data?.error ?? err?.data?.statusMessage ?? err?.statusMessage ?? err?.message ?? 'Something went wrong'
}

/** Poll a loader every `ms` while the page is mounted. */
export function usePolling(fn: () => Promise<unknown>, ms: number) {
  let t: ReturnType<typeof setInterval> | undefined
  onMounted(() => { fn(); t = setInterval(fn, ms) })
  onBeforeUnmount(() => clearInterval(t))
}
