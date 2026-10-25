class AiUsageBar < Formula
  desc "Menu bar app showing remaining usage limits for Antigravity, Claude Code and OpenCode"
  homepage "https://github.com/bpmiranda3099/ai-usage-bar-macos"
  url "https://github.com/bpmiranda3099/ai-usage-bar-macos/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "9ee384b01d5b0a44fe3d36f0e560afa97a8fde71abc00b9e706ca62218c2c785"
  license "MIT"
  head "https://github.com/bpmiranda3099/ai-usage-bar-macos.git", branch: "main"

  depends_on macos: :tahoe

  def install
    system "swift", "build", "--disable-sandbox", "--configuration", "release"
    libexec.install ".build/release/AIAgentsUsageBar",
                    ".build/release/ai-agents-usage-bar_UsageBarCore.bundle"
    bin.write_exec_script libexec/"AIAgentsUsageBar"
  end

  service do
    run [opt_libexec/"AIAgentsUsageBar"]
    run_type :immediate
    process_type :interactive
  end

  test do
    assert_path_exists libexec/"AIAgentsUsageBar"
  end
end
