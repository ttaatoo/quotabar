# frozen_string_literal: true

class Quotabar < Formula
  desc "macOS menu bar quota for Cursor, ChatGPT, GLM, and Grok"
  homepage "https://github.com/ttaatoo/quotabar"
  # Fill sha256 with the real digest after the v0.0.10 tag exists.
  # Until then, install from git: brew install --HEAD ttaatoo/quotabar/quotabar
  url "https://github.com/ttaatoo/quotabar/archive/refs/tags/v0.0.10.tar.gz"
  sha256 :no_check
  license "MIT"
  head "https://github.com/ttaatoo/quotabar.git", branch: "main"

  depends_on macos: :sonoma
  depends_on xcode: ["15.4", :build]

  def install
    system "bash", "scripts/package.sh"
    prefix.install "dist/QuotaBar.app"
    (bin/"quotabar").write <<~EOS
      #!/bin/bash
      exec open "#{prefix}/QuotaBar.app"
    EOS
    chmod 0755, bin/"quotabar"
  end

  def caveats
    <<~EOS
      QuotaBar is ad-hoc signed (no Apple Developer ID).

        xattr -dr com.apple.quarantine #{prefix}/QuotaBar.app

      Optional symlink:

        ln -sf #{prefix}/QuotaBar.app /Applications/QuotaBar.app

      First open: System Settings → Privacy & Security → Open Anyway.
    EOS
  end

  test do
    assert_path_exists prefix/"QuotaBar.app"
  end
end
