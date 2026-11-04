require "test_helper"

class RailsInformant::JavascriptStackTest < ActiveSupport::TestCase
  ORIGIN = "https://shop.example"

  StubAsset = Data.define(:logical_path, :path)

  class StubLoadPath
    def initialize(assets)
      @assets = assets.index_by { it.logical_path.to_s }
    end

    def find(logical_path) = @assets[logical_path]
  end

  setup do
    assets = [
      StubAsset.new(logical_path: Pathname("controllers/cart_controller.js"), path: Rails.root.join("app/javascript/controllers/cart_controller.js")),
      StubAsset.new(logical_path: Pathname("application.js"), path: Rails.root.join("app/javascript/application.js")),
      StubAsset.new(logical_path: Pathname("chart.js"), path: Rails.root.join("vendor/javascript/chart.js")),
      StubAsset.new(logical_path: Pathname("turbo.min.js"), path: Pathname("/gems/turbo-rails/app/assets/javascripts/turbo.min.js"))
    ]
    Rails.application.stubs(:assets).returns(stub(load_path: StubLoadPath.new(assets)))
    Rails.application.config.stubs(:assets).returns(ActiveSupport::OrderedOptions.new.merge!(prefix: "/assets"))
  end

  test "a Chrome stack and a Firefox stack for the same error yield the same ordered frames" do
    chrome = <<~STACK
      TypeError: Cannot read properties of null (reading 'value')
          at CartController.connect (https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js:42:15)
          at async load (https://shop.example/assets/application-9f8e7d6c.js:7:3)
          at https://shop.example/assets/application-9f8e7d6c.js:12:1
    STACK
    firefox = <<~STACK
      connect@https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js:42:15
      load*@https://shop.example/assets/application-9f8e7d6c.js:7:3
      @https://shop.example/assets/application-9f8e7d6c.js:12:1
    STACK

    chrome_frames = parse(chrome).frames
    firefox_frames = parse(firefox).frames

    assert_equal firefox_frames, chrome_frames
    assert_equal [ "connect", "load", "<anonymous>" ], chrome_frames.map(&:function)
    assert_equal [ 42, 7, 12 ], chrome_frames.map(&:line)
    assert_equal [ 15, 3, 1 ], chrome_frames.map(&:column)
  end

  test "a digested asset URL maps to the app source file and renders like a Ruby frame" do
    stack = parse "    at CartController.connect (https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js:42:15)"

    frame = stack.frames.first
    assert_equal "app/javascript/controllers/cart_controller.js", frame.path
    assert frame.app?
    assert_equal [ "app/javascript/controllers/cart_controller.js:42:15:in 'connect'" ], stack.backtrace
  end

  test "an unknown asset keeps its URL and is not an app frame" do
    url = "https://shop.example/assets/controllers/missing_controller-3a1b2c4d.js"
    frame = parse("    at go (#{url}:1:2)").frames.first

    assert_equal url, frame.path
    assert_not frame.app?
  end

  test "frames are kept as URLs and non-app when the host has no Propshaft load path" do
    Rails.application.stubs(:assets).returns(nil)
    url = "https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js"
    frame = parse("    at go (#{url}:1:2)").frames.first

    assert_equal url, frame.path
    assert_not frame.app?
  end

  test "vendored pins, gem assets, other origins and extensions are non-app and skipped for the first app frame" do
    stack = parse <<~STACK
          at Chart.draw (chrome-extension://abcdefghijklmnop/content.js:1:100)
          at Chart.render (https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.js:13:2000)
          at Chart.update (https://shop.example/assets/chart-0a1b2c3d.js:5:10)
          at Session.visit (https://shop.example/assets/turbo.min-4e5f6a7b.js:1:500)
          at CartController.connect (https://evil.example/assets/controllers/cart_controller-3a1b2c4d.js:1:1)
          at async CartController.add (https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js:42:15)
    STACK

    assert_equal [ false, false, false, false, false, true ], stack.frames.map(&:app?)
    assert_equal "vendor/javascript/chart.js", stack.frames[2].path
    assert_equal "https://shop.example/assets/turbo.min-4e5f6a7b.js", stack.frames[3].path
    assert_equal "app/javascript/controllers/cart_controller.js:add", stack.first_app_frame.fingerprint_key
  end

  test "a stack with more than 50 frames is truncated to 50" do
    lines = 60.times.map { "    at f#{it} (https://shop.example/assets/application-9f8e7d6c.js:#{it + 1}:1)" }
    stack = parse lines.join("\n")

    assert_equal 50, stack.frames.size
    assert_equal 50, stack.backtrace.size
    assert_equal "f49", stack.frames.last.function
  end

  test "a stack with no parseable frame has no app frame and keeps its raw lines" do
    stack = parse "Error: something broke\n    at <anonymous>\n"

    assert_empty stack.frames
    assert_nil stack.first_app_frame
    assert_equal [ "Error: something broke", "    at <anonymous>" ], stack.backtrace
  end

  test "a nil stack is empty" do
    stack = parse nil

    assert_empty stack.frames
    assert_empty stack.backtrace
    assert_nil stack.first_app_frame
  end

  test "function names normalize across engines" do
    {
      "CartController.connect" => "connect",
      "async CartController.add" => "add",
      "new CartController" => "CartController",
      "load*" => "load",
      "connect/<" => "<anonymous>",
      "Object.<anonymous>" => "<anonymous>",
      "global code" => "<anonymous>",
      "module code" => "<anonymous>",
      "" => "<anonymous>",
      nil => "<anonymous>"
    }.each do |raw, normalized|
      assert_equal normalized, RailsInformant::JavascriptStack.normalize_function(raw), "for #{raw.inspect}"
    end
  end

  private

  def parse(stack) = RailsInformant::JavascriptStack.parse(stack, origin: ORIGIN)
end
