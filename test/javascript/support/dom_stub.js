// Just enough of window and document for the client module: event targets,
// meta lookup, location, navigator.sendBeacon, fetch and element ancestry.

export class StubElement {
  constructor (tag, attributes = {}, { parent = null, text = '' } = {}) {
    this.tagName = tag.toUpperCase()
    this.attributes = attributes
    this.id = attributes.id ?? ''
    this.parentElement = parent
    this.textContent = text
  }

  getAttribute (name) {
    return this.attributes[name] ?? null
  }

  closest (selectors) {
    const tests = selectors.split(',').map(selector => {
      const attribute = selector.trim().match(/^\[([\w-]+)\]$/)?.[1]
      return attribute
        ? element => element.getAttribute(attribute) !== null
        : element => element.tagName === selector.trim().toUpperCase()
    })
    for (let element = this; element; element = element.parentElement) {
      if (tests.some(test => test(element))) return element
    }
    return null
  }
}

export function withTarget (event, target) {
  Object.defineProperty(event, 'target', { value: target })
  return event
}

export function createWindow ({
  context = 'BLOB',
  endpoint = '/informant/browser_reports',
  href = 'https://app.test/cart?step=2#summary',
  respond = () => new Response(null, { status: 204 }),
  sendBeacon = true
} = {}) {
  const metas = { 'informant-browser': context, 'informant-browser-endpoint': endpoint }
  const document = new EventTarget()
  document.visibilityState = 'visible'
  document.querySelector = selector => {
    const name = selector.match(/^meta\[name="([^"]+)"\]$/)?.[1]
    return name && name in metas ? { content: metas[name] } : null
  }

  const win = new EventTarget()
  win.document = document
  win.location = new URL(href)
  win.onerror = null
  win.fetches = []
  win.beacons = []
  win.metas = metas
  win.fetch = async (input, init = {}) => {
    win.fetches.push({ init, url: String(input) })
    return respond(String(input), init)
  }
  win.navigator = sendBeacon
    ? { sendBeacon: (url, blob) => { win.beacons.push({ blob, url }); return true } }
    : {}

  win.reportRequests = () => win.fetches.filter(({ url }) => url === metas['informant-browser-endpoint'])
  win.reports = () => win.reportRequests().flatMap(({ init }) => JSON.parse(init.body).reports)
  return win
}

export function dispatch (target, type, { detail, eventTarget } = {}) {
  const event = new CustomEvent(type, { cancelable: true, detail })
  if (eventTarget) withTarget(event, eventTarget)
  target.dispatchEvent(event)
  return event
}

export function rejection (reason) {
  const event = new Event('unhandledrejection')
  event.reason = reason
  return event
}
