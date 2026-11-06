# Maps the digested asset URLs these tests use to app sources without
# Propshaft, which the dummy app does not load.
module JavascriptAssetStubs
  ORIGIN = "https://shop.example"

  StubAsset = Data.define(:logical_path, :path)

  class StubLoadPath
    def initialize(assets)
      @assets = assets.index_by { it.logical_path.to_s }
    end

    def find(logical_path) = @assets[logical_path]
  end

  private

  def stub_javascript_assets
    assets = [
      StubAsset.new(logical_path: Pathname("controllers/cart_controller.js"), path: Rails.root.join("app/javascript/controllers/cart_controller.js")),
      StubAsset.new(logical_path: Pathname("controllers/search_controller.js"), path: Rails.root.join("app/javascript/controllers/search_controller.js")),
      StubAsset.new(logical_path: Pathname("chart.js"), path: Rails.root.join("vendor/javascript/chart.js")),
      StubAsset.new(logical_path: Pathname("turbo.min.js"), path: Pathname("/gems/turbo-rails/app/assets/javascripts/turbo.min.js"))
    ]
    Rails.application.stubs(:assets).returns(stub(load_path: StubLoadPath.new(assets)))
    Rails.application.config.stubs(:assets).returns(ActiveSupport::OrderedOptions.new.merge!(prefix: "/assets"))
  end
end
