module RailsInformant
  module BrowserHelper
    # Module scripts run in document order, so an app module that throws while
    # evaluating would beat the pinned module to it. This classic script buffers
    # errors from the start and hands them to the module once it loads.
    EARLY_HOOK = <<~JS.freeze
      (() => {
        const state = { queue: [], previousOnerror: window.onerror }
        state.onerror = (...args) => {
          state.queue.push({ type: 'error', args })
          return state.previousOnerror ? state.previousOnerror(...args) : false
        }
        state.onrejection = event => state.queue.push({ type: 'rejection', reason: event.reason })
        window.onerror = state.onerror
        window.addEventListener('unhandledrejection', state.onrejection)
        window.__railsInformant = state
        const load = () => import('rails_informant')
        document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', load, { once: true }) : load()
      })()
    JS

    # The flag is read here rather than at boot because hosts set it in an
    # initializer, which runs after the engine's.
    def informant_browser_tag
      return unless RailsInformant.config.capture_browser_errors

      safe_join [
        tag.meta(name: "informant-browser", content: RailsInformant::BrowserContext.generate(request)),
        tag.meta(name: "informant-browser-endpoint", content: rails_informant.browser_reports_path),
        javascript_tag(EARLY_HOOK, nonce: true)
      ], "\n"
    end
  end
end
