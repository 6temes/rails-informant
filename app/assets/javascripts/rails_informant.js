const BUDGET = 10
const CRUMBS = 20
const DEDUPE_MS = 5000
const FLUSH_MS = 1000
// The server rejects a body over 64 KB whole, and browsers cap keepalive and beacon bodies at 64 KiB.
const MAX_BODY = 60000
const MAX_REPORTS = 10
// Turbo's minified build mangles the error class name, so its rejection is recognised by this text.
const FRAME_MISSING = 'did not contain the expected <turbo-frame'
// WebKit, Chromium and Firefox wordings for a fetch the network dropped.
const NETWORK_FAILURES = new Set(['Load failed', 'Failed to fetch', 'NetworkError when attempting to fetch resource.'])
const V8_FRAME = /^\s*at (?:.+? \()?(\S+?):\d+:\d+\)?$/
const FIREFOX_FRAME = /^\s*[^@]*@(.+):\d+:\d+$/

const clip = (value, length) => String(value ?? '').slice(0, length)
const frameUrl = line => (line.match(V8_FRAME) || line.match(FIREFOX_FRAME))?.[1]
const topFrame = stack => String(stack).split('\n').find(frameUrl) || ''
const withoutFragment = href => href.split('#')[0]
const meta = (document, name) => document.querySelector(`meta[name="${name}"]`)?.content

// documentUrl is passed only when the app has no inline scripts, so a frame on the page itself was injected.
export const isNoise = ({ error, message, name, stack }, origin, documentUrl) => {
  if (!error && /^Script error\.?$/.test(message)) return true
  if (/ResizeObserver loop/.test(message)) return true
  if (name === 'TypeError' && NETWORK_FAILURES.has(message)) return true
  const url = frameUrl(topFrame(stack))
  return Boolean(url) && (!url.startsWith(`${origin}/`) || url === documentUrl)
}

export const signature = ({ message, name, stack }) => `${name}|${message}|${topFrame(stack)}`

export const classifyFrameMissing = response => {
  if (response.redirected) return 'drop'
  return response.ok ? 'report' : 'breadcrumb'
}

export const chooseTransport = (trigger, navigator) =>
  (trigger === 'pagehide' || trigger === 'visibilitychange') && navigator.sendBeacon ? 'beacon' : 'fetch'

export const buildReport = (kind, { message, name, stack }, { breadcrumbs, context, failingRequestId, url }) => ({
  breadcrumbs: breadcrumbs.slice(-CRUMBS),
  context,
  failing_request_id: failingRequestId,
  kind,
  message: clip(message, 1000),
  name: clip(name, 100),
  occurred_at: new Date().toISOString(),
  stack: String(stack).split('\n').slice(0, 50).join('\n').slice(0, 20000),
  url: clip(withoutFragment(url), 2000)
})

export class Budget {
  #left = BUDGET

  take () {
    if (this.#left === 0) return false
    this.#left--
    return true
  }

  reset () {
    this.#left = BUDGET
  }
}

export class Breadcrumbs {
  #crumbs = []
  failingRequestId = null

  add (category, message, metadata = {}) {
    this.#crumbs.push({ category, duration: null, message: clip(message, 500), metadata, timestamp: new Date().toISOString() })
    if (this.#crumbs.length > CRUMBS) this.#crumbs.shift()
  }

  // A Turbo request is seen by both the fetch wrapper and Turbo's own events.
  fetchError (message, status, requestId) {
    const last = this.#crumbs.at(-1)
    const seen = requestId
      ? this.#crumbs.some(it => it.metadata.request_id === requestId)
      : last?.category === 'fetch.error' && last.message === clip(message, 500) && last.metadata.status === status
    if (seen) return
    this.add('fetch.error', message, { request_id: requestId, status })
    if (requestId) this.failingRequestId = requestId
  }

  all () {
    return [...this.#crumbs]
  }
}

const describe = (value, fallback) => value && typeof value === 'object'
  ? { error: value, message: String(value.message ?? value), name: String(value.name || 'Error'), stack: String(value.stack || '') }
  : { error: value, message: String(value ?? fallback), name: 'Error', stack: '' }

export function start (win) {
  const { document, location, navigator } = win
  const budget = new Budget()
  const crumbs = new Breadcrumbs()
  const networkFailures = new WeakSet()
  const seen = new Map()
  const send = win.fetch
  const state = win.__railsInformant
  let bytes = 0
  let queue = []
  let timer

  const path = href => {
    const url = new URL(href, location.href)
    return (url.origin === location.origin ? '' : url.origin) + url.pathname + url.search
  }
  const endpoint = () => meta(document, 'informant-browser-endpoint')
  const isEndpoint = href => withoutFragment(new URL(href, location.href).href).startsWith(new URL(endpoint(), location.href).href)

  const flush = trigger => {
    clearTimeout(timer)
    if (!queue.length) return
    const body = JSON.stringify({ v: 1, reports: queue })
    queue = []
    bytes = 0
    if (chooseTransport(trigger, navigator) === 'beacon') {
      navigator.sendBeacon(endpoint(), new Blob([body], { type: 'text/plain' }))
    } else {
      // A failed send must not surface as an unhandled rejection, which would be reported in turn.
      send.call(win, endpoint(), {
        body,
        credentials: 'same-origin',
        headers: { 'Content-Type': 'text/plain' },
        keepalive: true,
        method: 'POST'
      }).catch(() => {})
    }
  }

  const enqueue = report => {
    const size = new TextEncoder().encode(JSON.stringify(report)).length + 1
    if (queue.length && (bytes + size > MAX_BODY || queue.length >= MAX_REPORTS)) flush('size')
    queue.push(report)
    bytes += size
    clearTimeout(timer)
    timer = setTimeout(() => flush('timer'), FLUSH_MS)
  }

  const capture = (kind, details) => {
    const inlineScripts = meta(document, 'informant-browser-inline-scripts') !== 'false'
    if (isNoise(details, location.origin, inlineScripts ? undefined : withoutFragment(location.href))) return
    const now = Date.now()
    for (const [key, at] of seen) if (now - at >= DEDUPE_MS) seen.delete(key)
    const key = signature(details)
    if (seen.has(key)) return
    seen.set(key, now)
    if (!budget.take()) return
    enqueue(buildReport(kind, details, {
      breadcrumbs: crumbs.all(),
      context: meta(document, 'informant-browser'),
      failingRequestId: crumbs.failingRequestId,
      url: location.href
    }))
  }

  const onError = (message, source, lineno, colno, error) => {
    const details = describe(error, message)
    if (!details.stack && source) details.stack = `@${source}:${lineno}:${colno}`
    capture('error', details)
  }

  // Turbo rethrows network failures and frame-missing errors from un-awaited promises; its events already classified them.
  const onRejection = reason => {
    if (networkFailures.has(reason)) return
    const details = describe(reason)
    if (!details.message.includes(FRAME_MISSING)) capture('rejection', details)
  }

  if (state) win.removeEventListener('unhandledrejection', state.onrejection)
  const previous = state && win.onerror === state.onerror ? state.previousOnerror : win.onerror
  win.onerror = (...args) => {
    onError(...args)
    return previous ? previous.apply(win, args) : false
  }
  win.addEventListener('unhandledrejection', event => onRejection(event.reason))

  win.fetch = async function (input, init) {
    const href = String(input?.url ?? input)
    try {
      const response = await send.call(win, input, init)
      if (response.status >= 500 && !isEndpoint(href)) crumbs.fetchError(path(href), response.status, response.headers.get('X-Request-Id'))
      return response
    } catch (error) {
      if (error?.name !== 'AbortError' && !isEndpoint(href)) crumbs.fetchError(path(href), null, null)
      throw error
    }
  }

  document.addEventListener('click', ({ target }) => {
    if (!target?.closest) return
    const element = target.closest('[data-action],a,button,input,select,textarea,label') || target
    const tag = element.tagName.toLowerCase()
    const metadata = { tag }
    if (element.id) metadata.id = clip(element.id, 100)
    const action = element.closest('[data-action]')?.getAttribute('data-action')
    const controller = element.closest('[data-controller]')?.getAttribute('data-controller')
    if (action) metadata.action = clip(action, 200)
    if (controller) metadata.controller = clip(controller, 200)
    crumbs.add('ui.click', element.id ? `${tag}#${metadata.id}` : tag, metadata)
  }, true)

  document.addEventListener('turbo:visit', ({ detail }) => crumbs.add('turbo.visit', path(detail.url), { action: detail.action }))
  document.addEventListener('turbo:load', ({ detail }) => {
    budget.reset()
    crumbs.add('turbo.visit', path(detail?.url ?? location.href))
  })
  document.addEventListener('turbo:before-fetch-response', ({ detail: { fetchResponse } }) => {
    const { response, statusCode } = fetchResponse
    if (statusCode >= 500) crumbs.fetchError(path(response.url), statusCode, response.headers.get('X-Request-Id'))
  })
  document.addEventListener('turbo:fetch-request-error', ({ detail }) => {
    networkFailures.add(detail.error)
    crumbs.fetchError(path(detail.request.url.href), null, null)
  })
  document.addEventListener('turbo:frame-missing', ({ detail: { response }, target }) => {
    const verdict = classifyFrameMissing(response)
    if (verdict === 'report') {
      capture('turbo', {
        message: `The response (${response.status}) did not contain the expected <turbo-frame id="${target.id}">`,
        name: 'TurboFrameMissingError',
        stack: ''
      })
    } else if (verdict === 'breadcrumb') {
      crumbs.fetchError(path(response.url), response.status, response.headers.get('X-Request-Id'))
    }
  })

  win.addEventListener('pagehide', () => flush('pagehide'))
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') flush('visibilitychange')
  })

  if (state) {
    for (const item of state.queue) item.type === 'error' ? onError(...item.args) : onRejection(item.reason)
    delete win.__railsInformant
  }
}

if (typeof document !== 'undefined' && document.querySelector('meta[name="informant-browser"]')) start(window)
