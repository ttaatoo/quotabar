#!/usr/bin/env bash
# Compile and run scripts/linux-foundation-tests.swift against the real sources.
# This list intentionally excludes CursorAuth, CursorClient, FixtureLoader, and
# RefreshWork so Linux does not need a SQLite3 module. Cancellation mapping is
# QuotaError.captured. macOS CI should still run xcodebuild test.
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -swift-version 5 -O -o /tmp/qb-foundation-tests \
  QuotaBar/Models/QuotaError.swift \
  QuotaBar/Models/ProviderKind.swift \
  QuotaBar/Models/PopoverTab.swift \
  QuotaBar/Models/UsageModels.swift \
  QuotaBar/Models/AppSettings.swift \
  QuotaBar/Services/JSONSupport.swift \
  QuotaBar/Services/TimeFormatting.swift \
  QuotaBar/Services/HTTPClassify.swift \
  QuotaBar/Services/HTTPClient.swift \
  QuotaBar/Services/RefreshWork.swift \
  QuotaBar/Services/RefreshCoordinator.swift \
  QuotaBar/Services/KeychainStore.swift \
  QuotaBar/Services/QuotaBarLog.swift \
  QuotaBar/Services/ConfigStore.swift \
  QuotaBar/Providers/CodexCLIAuth.swift \
  QuotaBar/Providers/ChatGPTAccountIdentity.swift \
  QuotaBar/Providers/ChatGPTClient.swift \
  QuotaBar/Providers/GrokAuth.swift \
  QuotaBar/Providers/GrokAccountIdentity.swift \
  QuotaBar/Providers/GrokClient.swift \
  QuotaBar/Providers/OpenCodeGoClient.swift \
  QuotaBar/Providers/GLMClient.swift \
  scripts/linux-foundation-tests.swift
/tmp/qb-foundation-tests
