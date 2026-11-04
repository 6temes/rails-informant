import { afterEach, beforeEach, describe, mock, test } from 'node:test'
import assert from 'node:assert/strict'
import {
  Breadcrumbs,
  Budget,
  buildReport,
  chooseTransport,
  classifyFrameMissing,
  isNoise,
  signature,
  start
} from '../../app/assets/javascripts/rails_informant.js'
import { StubElement, createWindow, dispatch, rejection, withTarget } from './support/dom_stub.js'

const ORIGIN = 'https://app.test'
const APP_STACK = `TypeError: Cannot read properties of null (reading 'id')
    at CartController.connect (${ORIGIN}/assets/controllers/cart_controller-3f2a1b9c.js:12:7)
    at ${ORIGIN}/assets/stimulus-9a8b7c6d.js:1:2000`
const FRAME_MISSING_MESSAGE = 'The response (200) did not contain the expected <turbo-frame id="cart"> and will be ignored. To perform a full page visit instead, set turbo-visit-control to reload.'

const appError = (message = 'boom', stack = APP_STACK) => Object.assign(new TypeError(message), { stack })
const throwIn = (win, error) => win.onerror(`Uncaught ${error}`, `${ORIGIN}/assets/application.js`, 1, 1, error)
const pick = (object, ...keys) => Object.fromEntries(keys.map(key => [key, object[key]]))
const settle = async () => {
  mock.timers.tick(1000)
  await new Promise(resolve => setImmediate(resolve))
}
const frameResponse = ({ ok = true, redirected = false, requestId = null, status = 200 } = {}) => ({
  headers: new Headers(requestId ? { 'X-Request-Id': requestId } : {}),
  ok,
  redirected,
  status,
  url: `${ORIGIN}/cart/frame`
})

beforeEach(() => mock.timers.enable({ apis: ['setTimeout', 'Date'], now: Date.parse('2026-11-01T10:00:00Z') }))
afterEach(() => mock.timers.reset())

describe('importing the module', () => {
  test('touches no globals when there is no window or meta', async () => {
    const before = Object.keys(globalThis).sort()
    await import(`../../app/assets/javascripts/rails_informant.js?fresh=${Date.now()}`)
    assert.deepEqual(Object.keys(globalThis).sort(), before)
    assert.equal(globalThis.window, undefined)
  })
})

describe('isNoise', () => {
  test('drops cross-origin "Script error." that arrives without an error object', () => {
    assert.equal(isNoise({ message: 'Script error.', stack: '' }, ORIGIN), true)
  })

  test('drops the ResizeObserver loop warnings', () => {
    assert.equal(isNoise({ message: 'ResizeObserver loop limit exceeded', stack: '' }, ORIGIN), true)
    assert.equal(isNoise({ message: 'ResizeObserver loop completed with undelivered notifications.', stack: '' }, ORIGIN), true)
  })

  test('drops errors whose top frame is an extension or another origin', () => {
    const extension = 'TypeError: x\n    at inject (chrome-extension://abcdef/content.js:1:10)\n    at https://app.test/assets/app.js:1:1'
    const thirdParty = 'widget@https://cdn.example.com/widget.js:4:2\n@https://app.test/assets/app.js:1:1'
    assert.equal(isNoise({ error: {}, message: 'x', stack: extension }, ORIGIN), true)
    assert.equal(isNoise({ error: {}, message: 'x', stack: thirdParty }, ORIGIN), true)
  })

  test('keeps app errors and Stimulus wrapper calls that carry the error', () => {
    assert.equal(isNoise({ error: {}, message: 'boom', stack: APP_STACK }, ORIGIN), false)
    assert.equal(isNoise({ error: new Error('boom'), message: 'boom', stack: '' }, ORIGIN), false)
  })
})

describe('signature', () => {
  test('combines name, message and the top frame', () => {
    assert.equal(
      signature({ message: 'boom', name: 'TypeError', stack: APP_STACK }),
      `TypeError|boom|    at CartController.connect (${ORIGIN}/assets/controllers/cart_controller-3f2a1b9c.js:12:7)`
    )
  })
})

describe('Budget', () => {
  test('allows ten reports and refills on reset', () => {
    const budget = new Budget()
    const taken = Array.from({ length: 11 }, () => budget.take())
    assert.deepEqual(taken, [...Array(10).fill(true), false])
    budget.reset()
    assert.equal(budget.take(), true)
  })
})

describe('Breadcrumbs', () => {
  test('keeps the 20 most recent, oldest dropped first', () => {
    const crumbs = new Breadcrumbs()
    for (let i = 1; i <= 25; i++) crumbs.add('turbo.visit', `/page/${i}`)
    const all = crumbs.all()
    assert.equal(all.length, 20)
    assert.equal(all[0].message, '/page/6')
    assert.equal(all.at(-1).message, '/page/25')
    assert.deepEqual(Object.keys(all[0]).sort(), ['category', 'duration', 'message', 'metadata', 'timestamp'])
  })

  test('records a failing request once per request ID', () => {
    const crumbs = new Breadcrumbs()
    crumbs.fetchError('/cart', 500, 'req-1')
    crumbs.fetchError('/cart', 500, 'req-1')
    crumbs.fetchError('/cart', null, null)
    crumbs.fetchError('/cart', null, null)
    assert.deepEqual(crumbs.all().map(it => it.metadata), [{ request_id: 'req-1', status: 500 }, { request_id: null, status: null }])
    assert.equal(crumbs.failingRequestId, 'req-1')
  })
})

describe('classifyFrameMissing', () => {
  test('reports a successful response, keeps a failed one as a breadcrumb and drops a redirect', () => {
    assert.equal(classifyFrameMissing(frameResponse()), 'report')
    assert.equal(classifyFrameMissing(frameResponse({ ok: false, status: 500 })), 'breadcrumb')
    assert.equal(classifyFrameMissing(frameResponse({ redirected: true })), 'drop')
  })
})

describe('chooseTransport', () => {
  test('uses sendBeacon when the page is going away and fetch otherwise', () => {
    const navigator = { sendBeacon () {} }
    assert.equal(chooseTransport('pagehide', navigator), 'beacon')
    assert.equal(chooseTransport('visibilitychange', navigator), 'beacon')
    assert.equal(chooseTransport('timer', navigator), 'fetch')
  })
})

describe('buildReport', () => {
  test('carries only the wire keys and truncates message and stack', () => {
    const stack = Array.from({ length: 80 }, (_, i) => `    at f${i} (${ORIGIN}/assets/app.js:${i}:1)`).join('\n')
    const report = buildReport('error', { message: 'x'.repeat(5000), name: 'TypeError', stack }, {
      breadcrumbs: [], context: 'BLOB', failingRequestId: null, url: `${ORIGIN}/cart#top`
    })
    assert.deepEqual(Object.keys(report).sort(), ['breadcrumbs', 'context', 'failing_request_id', 'kind', 'message', 'name', 'occurred_at', 'stack', 'url'])
    assert.equal(report.message.length, 1000)
    assert.equal(report.stack.split('\n').length, 50)
    assert.equal(report.url, `${ORIGIN}/cart`)
    assert.equal(report.occurred_at, '2026-11-01T10:00:00.000Z')
  })
})

describe('start', () => {
  test('reports an uncaught error once with the page context, then posts it as JSON', async () => {
    const win = createWindow()
    start(win)
    throwIn(win, appError())
    await settle()

    const [request] = win.reportRequests()
    assert.equal(win.reportRequests().length, 1)
    assert.deepEqual(
      { ...request.init, body: undefined },
      { body: undefined, credentials: 'same-origin', headers: { 'Content-Type': 'text/plain' }, keepalive: true, method: 'POST' }
    )
    const body = JSON.parse(request.init.body)
    assert.equal(body.v, 1)
    assert.deepEqual(Object.keys(body), ['v', 'reports'])
    assert.equal(body.reports.length, 1)
    assert.deepEqual(pick(body.reports[0], 'context', 'kind', 'message', 'name', 'stack', 'url'), {
      context: 'BLOB', kind: 'error', message: 'boom', name: 'TypeError', stack: APP_STACK, url: `${ORIGIN}/cart?step=2`
    })
  })

  test('reads the context blob when the error is caught', async () => {
    const win = createWindow()
    start(win)
    win.metas['informant-browser'] = 'RENEWED'
    throwIn(win, appError())
    await settle()
    assert.equal(win.reports()[0].context, 'RENEWED')
  })

  test('reports a Stimulus wrapper call by the error it carries', async () => {
    const win = createWindow()
    start(win)
    win.onerror('Error invoking action "click->cart#add"\n\nTypeError: boom', '', 0, 0, appError())
    await settle()
    assert.equal(win.reports().length, 1)
    assert.equal(win.reports()[0].name, 'TypeError')
    assert.equal(win.reports()[0].message, 'boom')
  })

  test('reports an unhandled rejection with kind rejection', async () => {
    const win = createWindow()
    start(win)
    win.dispatchEvent(rejection(appError('async boom')))
    win.dispatchEvent(rejection(undefined))
    await settle()
    assert.deepEqual(win.reports().map(it => [it.kind, it.message]), [['rejection', 'async boom'], ['rejection', 'undefined']])
  })

  test('drops noise before it reaches the endpoint', async () => {
    const win = createWindow()
    start(win)
    win.onerror('Script error.', '', 0, 0, null)
    win.onerror('ResizeObserver loop completed with undelivered notifications.', '', 0, 0, null)
    win.onerror('Uncaught Error: x', 'chrome-extension://abc/inject.js', 3, 4, null)
    await settle()
    assert.equal(win.reportRequests().length, 0)
  })

  test('chains a previously assigned window.onerror', () => {
    const win = createWindow()
    const calls = []
    win.onerror = (...args) => { calls.push(args); return true }
    start(win)
    const error = appError()
    assert.equal(win.onerror('m', 's', 1, 2, error), true)
    assert.deepEqual(calls, [['m', 's', 1, 2, error]])
  })

  test('reports identical errors once per 5 seconds', async () => {
    const win = createWindow()
    start(win)
    throwIn(win, appError())
    throwIn(win, appError())
    mock.timers.tick(4000)
    throwIn(win, appError())
    await settle()
    assert.equal(win.reports().length, 1)

    mock.timers.tick(5000)
    throwIn(win, appError())
    await settle()
    assert.equal(win.reports().length, 2)
  })

  test('drops the 11th report on a page and resets the budget on turbo:load', async () => {
    const win = createWindow()
    start(win)
    for (let i = 1; i <= 11; i++) throwIn(win, appError(`boom ${i}`))
    await settle()
    assert.equal(win.reports().length, 10)

    dispatch(win.document, 'turbo:load', { detail: { url: `${ORIGIN}/next` } })
    throwIn(win, appError('after visit'))
    await settle()
    assert.equal(win.reports().length, 11)
  })

  test('records a click by element identity and never its text', async () => {
    const win = createWindow()
    start(win)
    const form = new StubElement('form', { 'data-controller': 'cart' })
    const button = new StubElement('button', { 'data-action': 'cart#add' }, { parent: form, text: 'Alice Smith' })
    const icon = new StubElement('svg', {}, { parent: button })
    win.document.dispatchEvent(withTarget(new Event('click'), icon))
    throwIn(win, appError())
    await settle()

    const [report] = win.reports()
    const click = report.breadcrumbs.at(-1)
    assert.equal(click.category, 'ui.click')
    assert.deepEqual(click.metadata, { action: 'cart#add', controller: 'cart', tag: 'button' })
    assert.doesNotMatch(JSON.stringify(report), /Alice/)
  })

  test('records Turbo visits as breadcrumbs with the path', async () => {
    const win = createWindow()
    start(win)
    dispatch(win.document, 'turbo:visit', { detail: { action: 'advance', url: `${ORIGIN}/orders?page=2` } })
    dispatch(win.document, 'turbo:load', { detail: { url: `${ORIGIN}/orders?page=2` } })
    throwIn(win, appError())
    await settle()
    assert.deepEqual(win.reports()[0].breadcrumbs.map(it => [it.category, it.message]), [['turbo.visit', '/orders?page=2'], ['turbo.visit', '/orders?page=2']])
  })

  test('a failing app fetch sets failing_request_id; a request to the endpoint records nothing', async () => {
    const win = createWindow({
      respond: url => new Response('', { headers: { 'X-Request-Id': url === '/cart' ? 'req-500' : 'req-endpoint' }, status: 500 })
    })
    start(win)
    await win.fetch('/informant/browser_reports', { body: JSON.stringify({ reports: [], v: 1 }), method: 'POST' })
    await win.fetch('/cart', { method: 'POST' })
    throwIn(win, appError())
    await settle()

    const [report] = win.reports()
    assert.equal(report.failing_request_id, 'req-500')
    assert.deepEqual(report.breadcrumbs.map(it => [it.category, it.message, it.metadata]), [['fetch.error', '/cart', { request_id: 'req-500', status: 500 }]])
  })

  test('a 422 app response is not a failing request', async () => {
    const win = createWindow({ respond: () => new Response('', { headers: { 'X-Request-Id': 'req-422' }, status: 422 }) })
    start(win)
    await win.fetch('/cart')
    throwIn(win, appError())
    await settle()
    assert.equal(win.reports()[0].failing_request_id, null)
    assert.equal(win.reports()[0].breadcrumbs.length, 0)
  })

  test('a 5xx Turbo response becomes the failing request once, even when the fetch wrapper also saw it', async () => {
    const win = createWindow({ respond: () => new Response('', { headers: { 'X-Request-Id': 'req-t' }, status: 503 }) })
    start(win)
    const response = await win.fetch(`${ORIGIN}/orders`)
    dispatch(win.document, 'turbo:before-fetch-response', { detail: { fetchResponse: { response, statusCode: 503 } } })
    throwIn(win, appError())
    await settle()
    const [report] = win.reports()
    assert.equal(report.failing_request_id, 'req-t')
    assert.equal(report.breadcrumbs.length, 1)
  })

  test('a dropped connection during a Turbo visit is a breadcrumb, never a report', async () => {
    const failure = appError('Failed to fetch')
    const win = createWindow({ respond: () => { throw failure } })
    start(win)
    await assert.rejects(win.fetch(`${ORIGIN}/orders`))
    dispatch(win.document, 'turbo:fetch-request-error', { detail: { error: failure, request: { url: new URL(`${ORIGIN}/orders`) } } })
    win.dispatchEvent(rejection(failure))
    await settle()
    assert.equal(win.reportRequests().length, 0)

    throwIn(win, appError())
    await settle()
    assert.deepEqual(win.reports()[0].breadcrumbs.map(it => [it.category, it.message, it.metadata]), [['fetch.error', '/orders', { request_id: null, status: null }]])
  })

  test('a frame-missing on a 500 plus Turbo\'s rejection reports nothing', async () => {
    const win = createWindow()
    start(win)
    const frame = new StubElement('turbo-frame', { id: 'cart' })
    const event = dispatch(win.document, 'turbo:frame-missing', { detail: { response: frameResponse({ ok: false, requestId: 'req-f', status: 500 }) }, eventTarget: frame })
    win.dispatchEvent(rejection(appError(FRAME_MISSING_MESSAGE.replace('200', '500'))))
    await settle()
    assert.equal(event.defaultPrevented, false)
    assert.equal(win.reportRequests().length, 0)
  })

  test('a frame-missing on a 200 plus Turbo\'s rejection reports once', async () => {
    const win = createWindow()
    start(win)
    const frame = new StubElement('turbo-frame', { id: 'cart' })
    const event = dispatch(win.document, 'turbo:frame-missing', { detail: { response: frameResponse() }, eventTarget: frame })
    win.dispatchEvent(rejection(appError(FRAME_MISSING_MESSAGE)))
    await settle()
    assert.equal(event.defaultPrevented, false)
    assert.equal(win.reports().length, 1)
    assert.deepEqual(pick(win.reports()[0], 'kind', 'name'), { kind: 'turbo', name: 'TurboFrameMissingError' })
    assert.match(win.reports()[0].message, /did not contain the expected <turbo-frame id="cart">/)
  })

  test('a 200 KB message still produces a body under 64 KB', async () => {
    const win = createWindow()
    start(win)
    throwIn(win, appError('x'.repeat(200 * 1024)))
    await settle()
    const [request] = win.reportRequests()
    assert.ok(new TextEncoder().encode(request.init.body).length < 64 * 1024)
  })

  test('splits queued reports into requests that each stay under 64 KB', async () => {
    const win = createWindow()
    start(win)
    const longFrame = `    at f (${ORIGIN}/assets/app.js?${'q'.repeat(400)}:1:1)`
    for (let i = 0; i < 4; i++) throwIn(win, appError(`boom ${i}`, Array(50).fill(longFrame).join('\n')))
    await settle()

    const requests = win.reportRequests()
    assert.equal(requests.length, 2)
    assert.equal(win.reports().length, 4)
    for (const { init } of requests) assert.ok(new TextEncoder().encode(init.body).length < 64 * 1024)
  })

  test('flushes with sendBeacon when the page is hidden or unloaded', async () => {
    const win = createWindow()
    start(win)
    throwIn(win, appError())
    win.document.visibilityState = 'hidden'
    win.document.dispatchEvent(new Event('visibilitychange'))
    throwIn(win, appError('second'))
    win.dispatchEvent(new Event('pagehide'))
    await settle()

    assert.equal(win.reportRequests().length, 0)
    assert.equal(win.beacons.length, 2)
    const [beacon] = win.beacons
    assert.equal(beacon.url, '/informant/browser_reports')
    assert.equal(beacon.blob.type, 'text/plain')
    assert.equal(JSON.parse(await beacon.blob.text()).reports[0].message, 'boom')
  })

  test('replays errors the early inline hook buffered before the module loaded, once', async () => {
    const win = createWindow()
    const previous = []
    win.onerror = (...args) => { previous.push(args); return false }
    const state = installEarlyHook(win)

    win.onerror('Uncaught TypeError: boom', `${ORIGIN}/assets/application.js`, 1, 1, appError())
    win.dispatchEvent(rejection(appError('early rejection')))
    start(win)
    win.dispatchEvent(rejection(appError('late rejection')))
    await settle()

    assert.deepEqual(win.reports().map(it => [it.kind, it.message]), [['error', 'boom'], ['rejection', 'early rejection'], ['rejection', 'late rejection']])
    assert.equal(previous.length, 1)
    assert.equal(win.__railsInformant, undefined)

    win.onerror('m', '', 0, 0, appError('chained'))
    assert.equal(previous.length, 2)
    assert.equal(state.queue.length, 2)
  })
})

// The inline classic script the layout helper emits, minus the dynamic import.
function installEarlyHook (window) {
  const state = { queue: [], previousOnerror: window.onerror }
  state.onerror = (...args) => {
    state.queue.push({ type: 'error', args })
    return state.previousOnerror ? state.previousOnerror(...args) : false
  }
  state.onrejection = event => state.queue.push({ type: 'rejection', reason: event.reason })
  window.onerror = state.onerror
  window.addEventListener('unhandledrejection', state.onrejection)
  window.__railsInformant = state
  return state
}
