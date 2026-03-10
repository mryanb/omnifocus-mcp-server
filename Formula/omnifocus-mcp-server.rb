# Homebrew formula for omnifocus-mcp-server
# To use: brew tap ryanbantz/tap && brew install omnifocus-mcp-server
class OmnifocusMcpServer < Formula
  desc "High-performance MCP server for OmniFocus"
  homepage "https://github.com/ryanbantz/omnifocus-mcp-server"
  url "https://github.com/ryanbantz/omnifocus-mcp-server/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on xcode: ["16.0", :build]
  depends_on :macos

  def install
    system "swift", "build",
           "--disable-sandbox",
           "-c", "release",
           "--arch", "arm64",
           "--arch", "x86_64"
    bin.install ".build/apple/Products/Release/omnifocus-mcp-server"
  end

  test do
    # Basic smoke test: binary runs and prints version info to stderr
    assert_match "omnifocus-mcp-server", shell_output("#{bin}/omnifocus-mcp-server --help 2>&1", 1)
  end
end
