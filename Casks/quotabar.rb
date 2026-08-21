# frozen_string_literal: true

cask "quotabar" do
  version "0.0.8"
  sha256 :no_check

  url "https://github.com/ttaatoo/quotabar/releases/download/v#{version}/QuotaBar.zip"
  name "QuotaBar"
  desc "Menu bar quota for Cursor, ChatGPT, GLM, and Grok"
  homepage "https://github.com/ttaatoo/quotabar"

  depends_on macos: :sonoma

  app "QuotaBar.app"

  caveats <<~EOS
    QuotaBar is ad-hoc signed (no Apple Developer ID). Install with:

      brew tap ttaatoo/quotabar https://github.com/ttaatoo/quotabar
      brew install --cask ttaatoo/quotabar/quotabar

    If Gatekeeper blocks the app:

      xattr -dr com.apple.quarantine /Applications/QuotaBar.app

    Then System Settings → Privacy & Security → Open Anyway.

    Upgrade:

      brew upgrade --cask ttaatoo/quotabar/quotabar
  EOS
end
